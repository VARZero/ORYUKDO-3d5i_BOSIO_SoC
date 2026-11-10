// Pin-level card plus mock DDR backend test boundary. Real loader and host RTL.
module tb_sd_storage(
 input wire clk,reset_n,
 output wire sd_clk,sd_cmd_o,sd_cmd_t,input wire sd_cmd_i,
 output wire [3:0] sd_dat_o,sd_dat_t,input wire [3:0] sd_dat_i,
 output wire boot_done,boot_failed,boot_en,boot_wr,boot_wen,
 output wire [28:0] boot_addr,output wire [255:0] boot_data,
 input wire app_rdy,app_wdf_rdy,rd_valid,input wire [255:0] rd_data,
 input wire awvalid,wvalid,bready,arvalid,rready,select_dma,
 input wire [31:0] address,write_data,
 output wire awready,wready,bvalid,arready,rvalid,
 output wire [31:0] read_data,output wire [1:0] bresp,rresp,
 output wire sd_irq,dma_irq,input wire [13:0] peek_word,output wire [31:0] peek_data
);
 import or_bo_axi_pkg::*;
 wire enable,request,ready,valid,complete,bad,take;wire [31:0] lba;wire [7:0] data;
 al_req_t q,sd_req,dma_req;al_rsp_t sd_rsp,dma_rsp,response;
 ax_req_t memory;ax_rsp_t reply;
 always_comb begin
  q='0;q.awaddr=address;q.araddr=address;q.wdata=write_data;q.wstrb=15;q.rmask=15;
  q.awvalid=awvalid;q.wvalid=wvalid;q.bready=bready;q.arvalid=arvalid;q.rready=rready;
  sd_req=select_dma?'0:q;dma_req=select_dma?q:'0;response=select_dma?dma_rsp:sd_rsp;
 end
 assign awready=response.awready;assign wready=response.wready;assign bvalid=response.bvalid;
 assign arready=response.arready;assign rvalid=response.rvalid;assign read_data=response.rdata;
 assign bresp=response.bresp;assign rresp=response.rresp;
 sd_boot #(.RAM_BYTES(4096)) loader(.clk,.reset(!reset_n),.calibrated(reset_n),.app_rdy,.app_wdf_rdy,
  .rd_valid,.rd_data,.en(boot_en),.write_cmd(boot_wr),.wdf_en(boot_wen),.addr(boot_addr),.wdata(boot_data),
  .done(boot_done),.failed(boot_failed),.enable,.request,.lba,.card_ready(ready),.valid,.complete,.card_bad(bad),.data,.take);
 or_sd_storage storage(.clk,.reset_n,.boot_done,.boot_enable(enable),.boot_request(request),.boot_lba(lba),
  .boot_ready(ready),.boot_valid(valid),.boot_data(data),.boot_take(take),.boot_complete(complete),.boot_failed(bad),
  .sd_req,.dma_req,.sd_rsp,.dma_rsp,.memory,.reply,.sd_irq,.dma_irq,
  .sd_clk,.sd_cmd_o,.sd_cmd_t,.sd_cmd_i,.sd_dat_o,.sd_dat_t,.sd_dat_i);
 axi_ram_model #(.WORDS(16384)) ram(.clk,.reset_n,.req(memory),.rsp(reply));
 assign peek_data=ram.mem[peek_word];
endmodule
