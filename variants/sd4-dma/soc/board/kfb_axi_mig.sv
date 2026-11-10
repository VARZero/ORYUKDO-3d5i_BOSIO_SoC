`timescale 1ns/1ps
// Full 32-bit AXI bursts to 256-bit MIG native lines. Addresses are physical,
// 0x80000000..0xbfffffff. Cache is private to one read burst, never retained
// across transactions, so other masters cannot leave stale CPU/DMA reads.
module kfb_axi_mig(
 input wire clk,reset_n,
 input or_bo_axi_pkg::ax_req_t req,output or_bo_axi_pkg::ax_rsp_t rsp,
 output wire native_valid,native_write,output wire [28:0] native_addr,
 output wire [255:0] native_data,output wire [31:0] native_mask,
 input wire native_ready,native_rvalid,input wire [255:0] native_rdata
);
 import or_bo_axi_pkg::*;
 typedef enum logic [3:0] {IDLE,READ_CMD,READ_WAIT,READ_REPLY,WRITE_DATA,WRITE_CMD,BREPLY,ERR_READ,ERR_WRITE} state_t;
 state_t state;
 ax_addr_t saved;logic [7:0] beat;logic [31:0] address,wdata,rdata;
 logic [3:0] wmask;logic bad_last;
 logic cache_valid;logic [24:0] cache_tag;logic [255:0] cache_data;
 logic [1:0] bresp;
 wire cache_hit=cache_valid && cache_tag==address[29:5];
 assign native_valid=reset_n && (state==WRITE_CMD || (state==READ_CMD && !cache_hit));
 assign native_write=state==WRITE_CMD;
 assign native_addr={1'b0,address[29:5],3'b000};
 assign native_data={8{wdata}};
 assign native_mask=~(32'(wmask)<<{address[4:2],2'b00});
 // Publish the packed response once. Zeroing the output struct before setting
 // its fields creates transient events around the fabric's packed request mux
 // in four-state event simulation, even though the settled logic is acyclic.
 always_comb begin : response_mux
  ax_rsp_t next_rsp;
  next_rsp='0;
  if(reset_n)case(state)
   IDLE:begin next_rsp.awready=1;next_rsp.arready=!req.awvalid;end
   READ_REPLY:begin next_rsp.rvalid=1;next_rsp.r.data=rdata;next_rsp.r.id=saved.id;next_rsp.r.last=beat==saved.len;end
   WRITE_DATA,ERR_WRITE:next_rsp.wready=1;
   BREPLY:begin next_rsp.bvalid=1;next_rsp.b.id=saved.id;next_rsp.b.resp=bresp;end
   ERR_READ:begin next_rsp.rvalid=1;next_rsp.r.id=saved.id;next_rsp.r.last=beat==saved.len;next_rsp.r.resp=DECERR;end
   default:begin end
  endcase
  rsp=next_rsp;
 end
 always_ff @(posedge clk)begin
  if(!reset_n)begin state<=IDLE;saved<='0;beat<=0;address<=0;wdata<=0;wmask<=0;
   rdata<=0;bad_last<=0;cache_valid<=0;cache_tag<=0;cache_data<=0;bresp<=0;end
  else case(state)
   IDLE:begin
    beat<=0;bad_last<=0;bresp<=OKAY;cache_valid<=0;
    if(req.awvalid)begin
     saved<=req.aw;address<=req.aw.addr[31:0];
     if(target(req.aw.addr)!=RAM_PORT || !legal(req.aw,1'b0))begin state<=ERR_WRITE;bresp<=DECERR;end
     else state<=WRITE_DATA;
    end else if(req.arvalid)begin
     saved<=req.ar;address<=req.ar.addr[31:0];
     state<=(target(req.ar.addr)==RAM_PORT && legal(req.ar,1'b0))?READ_CMD:ERR_READ;
    end
   end
   READ_CMD:if(cache_hit)begin rdata<=cache_data[address[4:2]*32+:32];state<=READ_REPLY;end
    else if(native_ready)state<=READ_WAIT;
   READ_WAIT:if(native_rvalid)begin
    cache_data<=native_rdata;cache_tag<=address[29:5];cache_valid<=1;
    rdata<=native_rdata[address[4:2]*32+:32];state<=READ_REPLY;
   end
   READ_REPLY:if(req.rready)begin
    if(beat==saved.len)state<=IDLE;
    else begin beat<=beat+1'b1;if(saved.burst==1)address<=address+4;state<=READ_CMD;end
   end
   WRITE_DATA:if(req.wvalid)begin
    wdata<=req.w.data;wmask<=req.w.strb;
    if(req.w.last!=(beat==saved.len))bad_last<=1;
    state<=WRITE_CMD;
   end
   WRITE_CMD:if(native_ready)begin
    if(beat==saved.len)begin state<=BREPLY;bresp<=bad_last?SLVERR:OKAY;end
    else begin beat<=beat+1'b1;if(saved.burst==1)address<=address+4;state<=WRITE_DATA;end
   end
   BREPLY:if(req.bready)state<=IDLE;
   ERR_READ:if(req.rready)begin if(beat==saved.len)state<=IDLE;else beat<=beat+1'b1;end
   ERR_WRITE:if(req.wvalid)begin if(beat==saved.len)state<=BREPLY;else beat<=beat+1'b1;end
   default:state<=IDLE;
  endcase
 end
 // synthesis translate_off
 always @(posedge clk)if(reset_n && native_rvalid)
  assert(state==READ_WAIT)else $fatal(1,"Unexpected AXI-MIG read completion");
 // synthesis translate_on
endmodule
