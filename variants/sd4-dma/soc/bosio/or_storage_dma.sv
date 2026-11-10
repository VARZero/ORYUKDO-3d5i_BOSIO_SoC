// One AXI owner, bounded 16-word bursts. Reads complete before writes are issued:
// this is required by the transaction-serialized CPU/BOSIO fabric.
module or_storage_dma(
 input wire clk,reset_n,
 input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp,
 output or_bo_axi_pkg::ax_req_t memory,input or_bo_axi_pkg::ax_rsp_t reply,
 output wire irq,
 input wire sd_start,sd_to_memory,input wire [31:0] sd_address,input wire [9:0] sd_bytes,
 output wire sd_ready,output logic sd_done,sd_error,
 output wire [8:0] buffer_address,output wire [7:0] buffer_wdata,
 output wire buffer_we,input wire [7:0] buffer_rdata
);
 import or_bo_axi_pkg::*;
 typedef enum logic [3:0] {IDLE,SETUP,AR,R,BUFFER_READ,BUFFER_WRITE,FILL,AW,W,B,NEXT,FINISH} state_t;
 state_t state;
 logic [31:0] source,dest,length,pattern,src,dst,left;
 logic [31:0] words[16];
 logic [4:0] count,index;
 logic [1:0] octet,operation;
 logic [8:0] buffer_pos;
 logic is_sd,sd_direction,failed,complete,irq_enable,queued,job_error;
 wire job_busy=queued || (state!=IDLE && !is_sd);
 wire valid,store;wire [31:0] address,write_data;wire [3:0] mask;
 logic [31:0] read_data;logic bus_error;
 gen3_axil_regs regs(.clk,.reset_n,.req,.rsp,.valid,.store,.address,.write_data,.mask,
  .ready(1'b1),.error(bus_error),.read_data);
 assign irq=complete && irq_enable;
 assign sd_ready=state==IDLE;
 assign buffer_address=buffer_pos;
 assign buffer_wdata=words[index[3:0]][8*octet+:8];
 assign buffer_we=state==BUFFER_WRITE;
 function automatic bit range_ok(input [31:0] base,input [31:0] bytes);
   logic [32:0] last;last={1'b0,base}+{1'b0,bytes};
   return base>=32'h80000000 && base<32'hc0000000 && last<=33'h0c0000000 && bytes!=0 && base[1:0]==0 && bytes[1:0]==0;
 endfunction
 always_comb begin
   bus_error=address[1:0]!=0 || (store && mask!=15);read_data=0;
   case(address[7:0])
    0:begin read_data=source;if(store && job_busy) bus_error=1;end
    4:begin read_data=dest;if(store && job_busy) bus_error=1;end
    8:begin read_data=length;if(store && job_busy) bus_error=1;end
    12:begin read_data=pattern;if(store && job_busy) bus_error=1;end
    16:begin read_data={23'b0,irq_enable,6'b0,operation};if(store && job_busy) bus_error=1;end
    20:begin read_data={29'b0,job_error,complete,job_busy};end
    default:bus_error=1;
   endcase
   memory='0;memory.ar.addr={32'b0,src};memory.aw.addr={32'b0,dst};
   memory.ar.len={3'b0,count}-8'd1;memory.aw.len={3'b0,count}-8'd1;
   memory.ar.size=2;memory.aw.size=2;memory.ar.burst=1;memory.aw.burst=1;
   memory.arvalid=state==AR;memory.rready=state==R;
   // A failed read must not publish AW: the serialized fabric would then wait
   // forever for write data from an operation already reporting failure.
   memory.awvalid=state==AW && !failed;memory.wvalid=state==W;
   memory.w.data=words[index[3:0]];memory.w.strb=15;memory.w.last=index==count-1'b1;
   memory.bready=state==B;
 end
 always_ff @(posedge clk) begin
   if(!reset_n) begin
     state<=IDLE;source<=0;dest<=0;length<=0;pattern<=0;src<=0;dst<=0;left<=0;
     count<=0;index<=0;octet<=0;operation<=0;buffer_pos<=0;is_sd<=0;sd_direction<=0;
     failed<=0;complete<=0;irq_enable<=0;sd_done<=0;sd_error<=0;queued<=0;job_error<=0;
   end else begin
     sd_done<=0;
     if(valid && store && !bus_error) case(address[7:0])
      0:source<=write_data;
      4:dest<=write_data;
      8:length<=write_data;
      12:pattern<=write_data;
      16:begin
        operation<=write_data[1:0];irq_enable<=write_data[8];complete<=0;queued<=1;

      end
      20:if(write_data[1]) complete<=0;
      default:;
     endcase
     case(state)
      IDLE: if(sd_start) begin
        is_sd<=1;sd_direction<=sd_to_memory;src<=sd_address;dst<=sd_address;
        left<={22'b0,sd_bytes};buffer_pos<=0;
        failed<=!range_ok(sd_address,{22'b0,sd_bytes}) || sd_bytes>512;
        state<=SETUP;
      end else if(queued) begin
        queued<=0;is_sd<=0;src<=source;dst<=dest;left<=length;
        failed<=!range_ok(dest,length) || (operation==1 && !range_ok(source,length)) ||
          (operation!=1 && operation!=2) ||
          (operation==1 && {1'b0,source}<{1'b0,dest}+{1'b0,length} && {1'b0,dest}<{1'b0,source}+{1'b0,length});
        state<=SETUP;
      end
      SETUP: begin
        index<=0;octet<=0;
        // 64-byte maximum, additionally split at both 4-KiB boundaries.
        count<=5'((left<64?left:32'd64)>>2);
        if((32'd4096-{20'b0,dst[11:0]})<(left<64?left:32'd64)) count<=5'((32'd4096-{20'b0,dst[11:0]})>>2);
        if((is_sd || operation==1) && (!is_sd || !sd_direction) &&
           (32'd4096-{20'b0,src[11:0]})<(left<64?left:32'd64) &&
           (32'd4096-{20'b0,src[11:0]})<=(32'd4096-{20'b0,dst[11:0]})) count<=5'((32'd4096-{20'b0,src[11:0]})>>2);
        if(failed) state<=FINISH;
        else if(is_sd && sd_direction) state<=BUFFER_READ;
        else if(!is_sd && operation==2) state<=FILL;
        else state<=AR;
      end
      AR:if(reply.arready) state<=R;
      R:if(reply.rvalid) begin
        words[index[3:0]]<=reply.r.data;
        if(reply.r.resp!=OKAY || reply.r.last!=(index==count-1'b1)) failed<=1;
        if(index==count-1'b1) begin index<=0;state<=is_sd?BUFFER_WRITE:AW;end
        else index<=index+1'b1;
      end
      BUFFER_READ:begin
        words[index[3:0]][8*octet+:8]<=buffer_rdata;buffer_pos<=buffer_pos+1'b1;octet<=octet+1'b1;
        if(octet==3) begin if(index==count-1'b1) begin index<=0;state<=AW;end else index<=index+1'b1;end
      end
      BUFFER_WRITE:begin
        buffer_pos<=buffer_pos+1'b1;octet<=octet+1'b1;
        if(octet==3) begin if(index==count-1'b1) begin index<=0;state<=NEXT;end else index<=index+1'b1;end
      end
      FILL:begin words[index[3:0]]<=pattern;if(index==count-1'b1) begin index<=0;state<=AW;end else index<=index+1'b1;end
      AW:if(failed) state<=FINISH;else if(reply.awready) state<=W;
      W:if(reply.wready) begin if(index==count-1'b1) state<=B;else index<=index+1'b1;end
      B:if(reply.bvalid) begin if(reply.b.resp!=OKAY) failed<=1;state<=NEXT;end
      NEXT:begin
        src<=src+{25'b0,count,2'b0};dst<=dst+{25'b0,count,2'b0};left<=left-{25'b0,count,2'b0};
        state<=(failed || left=={25'b0,count,2'b0})?FINISH:SETUP;
      end
      FINISH:begin
        if(is_sd) begin sd_done<=1;sd_error<=failed;end else begin complete<=1;job_error<=failed;end
        state<=IDLE;
      end
      default:;
     endcase
   end
 end
endmodule
