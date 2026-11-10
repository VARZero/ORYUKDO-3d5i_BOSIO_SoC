// Shared boot/Linux native SD host and DMA. Boot owns the card until boot_done;
// Linux then reinitializes in native mode through the command register interface.
module or_sd_storage(
 input wire clk,reset_n,boot_done,boot_enable,boot_request,input wire [31:0] boot_lba,
 output wire boot_ready,boot_valid,output wire [7:0] boot_data,input wire boot_take,
 output logic boot_complete,output wire boot_failed,
 input or_bo_axi_pkg::al_req_t sd_req,dma_req,
 output or_bo_axi_pkg::al_rsp_t sd_rsp,dma_rsp,
 output or_bo_axi_pkg::ax_req_t memory,input or_bo_axi_pkg::ax_rsp_t reply,
 output wire sd_irq,dma_irq,
 output wire sd_clk,sd_cmd_o,sd_cmd_t,input wire sd_cmd_i,
 output wire [3:0] sd_dat_o,sd_dat_t,input wire [3:0] sd_dat_i
);
 typedef enum logic [3:0] {POWER,INIT_SEND,INIT_WAIT,BOOT_IDLE,BOOT_SEND,BOOT_WAIT,BOOT_OUTPUT,
   RUNTIME,PRE_DMA,WAIT_PRE_DMA,SEND,WAIT_COMMAND,POST_DMA,WAIT_POST_DMA,COMPLETE,ERROR} state_t;
 state_t state;
 logic [16:0] power_count; // >= 74 clocks at 400 kHz before CMD0
 logic [3:0] init_step;
 logic [15:0] rca;
 logic [15:0] attempts;
 logic [8:0] boot_pos;
 logic [31:0] argument,cfg,command_cfg,dma_address;
 logic [9:0] length;
 logic [15:0] divider;
 logic irq_enable,complete;
 logic [2:0] failure;
 wire valid,store;wire [31:0] address,write_data;wire [3:0] mask;
 logic [31:0] read_data;logic bus_error;
 wire phy_busy,phy_done;wire [2:0] phy_error;wire [127:0] phy_response;
 logic phy_start;logic [5:0] phy_command;logic [31:0] phy_arg;
 logic [1:0] phy_response_type;logic phy_check,phy_wide,phy_data,phy_write;
 logic [9:0] phy_length;logic [15:0] phy_divider;
 wire dma_ready,dma_done,dma_error;wire [8:0] dma_buffer_address;wire [7:0] dma_buffer_data,buffer_data;
 wire dma_buffer_we;
 gen3_axil_regs bus(.clk,.reset_n,.req(sd_req),.rsp(sd_rsp),.valid,.store,.address,.write_data,.mask,
   .ready(1'b1),.error(bus_error),.read_data);
 assign boot_ready=state==BOOT_IDLE;
 assign boot_valid=state==BOOT_OUTPUT;
 assign boot_data=buffer_data;
 assign boot_failed=state==ERROR;
 assign sd_irq=complete && irq_enable;
 or_storage_dma dma(.clk,.reset_n,.req(dma_req),.rsp(dma_rsp),.memory,.reply,.irq(dma_irq),
   .sd_start((state==PRE_DMA || state==POST_DMA) && dma_ready),.sd_to_memory(state==POST_DMA),
   .sd_address(dma_address),.sd_bytes(length),.sd_ready(dma_ready),.sd_done(dma_done),.sd_error(dma_error),
   .buffer_address(dma_buffer_address),.buffer_wdata(dma_buffer_data),.buffer_we(dma_buffer_we),.buffer_rdata(buffer_data));
 or_sd_native phy(.clk,.reset_n,.start(phy_start),.command(phy_command),.argument(phy_arg),
   .response_type(phy_response_type),.check_crc(phy_check),.four_bit(phy_wide),.data_present(phy_data),
   .data_write(phy_write),.data_bytes(phy_length),.half_period(phy_divider),
   .busy(phy_busy),.done(phy_done),.error(phy_error),.response(phy_response),
   .buffer_address(boot_done?dma_buffer_address:boot_pos),.buffer_wdata(dma_buffer_data),
   .buffer_we(boot_done && dma_buffer_we),.buffer_rdata(buffer_data),
   .sd_clk,.sd_cmd_o,.sd_cmd_t,.sd_cmd_i,.sd_dat_o,.sd_dat_t,.sd_dat_i);
 always_comb begin
   phy_start=state==INIT_SEND || state==BOOT_SEND || state==SEND;
   phy_command=command_cfg[5:0];phy_arg=argument;phy_response_type=command_cfg[7:6];
   phy_check=command_cfg[8];phy_wide=cfg[0];phy_data=command_cfg[9];phy_write=command_cfg[10];
   phy_length=length;phy_divider=divider;
   if(!boot_done) begin
     phy_arg=0;phy_response_type=1;phy_check=1;phy_wide=0;phy_data=0;phy_write=0;phy_length=512;phy_divider=125;phy_command=0;
     case(init_step)
       0:begin phy_command=0;phy_response_type=0;end
       1:begin phy_command=8;phy_arg=32'h1aa;end
       2:phy_command=55;
       3:begin phy_command=41;phy_arg=32'h40ff8000;phy_check=0;end
       4:begin phy_command=2;phy_response_type=2;end
       5:phy_command=3;
       6:begin phy_command=7;phy_arg={rca,16'b0};phy_response_type=3;end
       7:begin phy_command=55;phy_arg={rca,16'b0};end
       8:begin phy_command=6;phy_arg=2;end
       default:;
     endcase
     if(state==BOOT_SEND || state==BOOT_WAIT || state==BOOT_OUTPUT || state==BOOT_IDLE) begin
       phy_command=17;phy_arg=boot_lba;phy_wide=1;phy_data=1;phy_divider=2;
     end
   end
   read_data=0;bus_error=address[1:0]!=0 || (store && mask!=15) || !boot_done;
   case(address[7:0])
     0:begin read_data=32'h53443431;if(store) bus_error=1;end
     4:begin read_data=argument;if(store && state!=RUNTIME) bus_error=1;end
     8:begin read_data=command_cfg;if(store && state!=RUNTIME) bus_error=1;end
     12:begin read_data={25'b0,failure,2'b0,complete,state!=RUNTIME};end
     16:begin read_data={16'b0,divider};if(store && state!=RUNTIME) bus_error=1;end
     20:begin read_data=cfg;if(store && state!=RUNTIME) bus_error=1;end
     24:begin read_data=dma_address;if(store && state!=RUNTIME) bus_error=1;end
     28:begin read_data={22'b0,length};if(store && state!=RUNTIME) bus_error=1;end
     32:begin read_data=phy_response[31:0];if(store) bus_error=1;end
     36:begin read_data=phy_response[63:32];if(store) bus_error=1;end
     40:begin read_data=phy_response[95:64];if(store) bus_error=1;end
     44:begin read_data=phy_response[127:96];if(store) bus_error=1;end
     48:read_data={31'b0,irq_enable};
     default:bus_error=1;
   endcase
 end
 always_ff @(posedge clk) begin
   if(!reset_n) begin
     state<=POWER;power_count<=0;init_step<=0;rca<=0;attempts<=0;boot_pos<=0;boot_complete<=0;
     argument<=0;cfg<=0;command_cfg<=0;dma_address<=0;length<=512;divider<=125;
     irq_enable<=0;complete<=0;failure<=0;
   end else begin
     boot_complete<=0;
     if(valid && store && !bus_error) case(address[7:0])
       4:argument<=write_data;
       8:begin command_cfg<=write_data;failure<=0;complete<=0;
          state<=write_data[9] && write_data[10]?PRE_DMA:SEND;end
       12:if(write_data[1]) complete<=0;
       16:divider<=write_data[15:0]<2?16'd2:write_data[15:0];
       20:cfg<=write_data;
       24:dma_address<=write_data;
       28:length<=write_data[9:0];
       48:irq_enable<=write_data[0];
       default:;
     endcase
     case(state)
       POWER:begin power_count<=power_count+1'b1;if(power_count==25000 && boot_enable) state<=INIT_SEND;end
       INIT_SEND:state<=INIT_WAIT;
       INIT_WAIT:if(phy_done) begin
         if(phy_error!=0) state<=ERROR;
         else if(init_step==1 && phy_response[11:0]!=12'h1aa) state<=ERROR;
         else if(init_step==3 && !phy_response[31]) begin
           attempts<=attempts+1'b1;init_step<=2;state<=attempts==65535?ERROR:INIT_SEND;
         end else if(init_step==3 && !phy_response[30]) state<=ERROR; // SDHC/SDXC only
         else if(init_step==8) state<=BOOT_IDLE;
         else begin
           if(init_step==5) rca<=phy_response[31:16];
           init_step<=init_step+1'b1;state<=INIT_SEND;
         end
       end
       BOOT_IDLE:if(boot_done) state<=RUNTIME;else if(boot_request) state<=BOOT_SEND;
       BOOT_SEND:state<=BOOT_WAIT;
       BOOT_WAIT:if(phy_done) begin if(phy_error!=0 || (phy_response[31:0]&32'hfdffe008)!=0) state<=ERROR;else begin boot_pos<=0;state<=BOOT_OUTPUT;end end
       BOOT_OUTPUT:if(boot_take) begin boot_pos<=boot_pos+1'b1;if(boot_pos==511) begin boot_complete<=1;state<=BOOT_IDLE;end end
       PRE_DMA:if(dma_ready) state<=WAIT_PRE_DMA;
       WAIT_PRE_DMA:if(dma_done) begin if(dma_error) begin failure<=5;state<=COMPLETE;end else state<=SEND;end
       SEND:state<=WAIT_COMMAND;
       WAIT_COMMAND:if(phy_done) begin
         failure<=phy_error;
         if(phy_error==0 && command_cfg[9] && !command_cfg[10]) state<=POST_DMA;
         else state<=COMPLETE;
       end
       POST_DMA:if(dma_ready) state<=WAIT_POST_DMA;
       WAIT_POST_DMA:if(dma_done) begin if(dma_error) failure<=5;state<=COMPLETE;end
       COMPLETE:begin complete<=1;state<=RUNTIME;end
       default:;
     endcase
   end
 end
endmodule
