`timescale 1ns/1ps
module tb_bosio_driver(
 input wire clk,reset_n,control_valid,control_write,
 input wire [31:0] control_address,control_wdata,
 output reg control_done,output reg [31:0] control_rdata,output reg control_error,
 input wire mem_we,input wire [21:0] mem_index,input wire [31:0] mem_wdata,
 output wire [31:0] mem_rdata,
 input wire video_ready,output wire video_valid,video_sof,video_eol,
 output wire [23:0] video_data,
 output reg [31:0] writes0,writes1,reads_out,
 output wire [31:0] active_scene
);
 import or_bo_axi_pkg::*;
 ax_req_t masters[4],memory;ax_rsp_t replies[4],memory_reply;
 al_req_t lite[LITE_PORTS],controls[3];al_rsp_t lite_reply[LITE_PORTS],control_replies[3];
 ax_req_t dma[3];ax_rsp_t dma_reply[3];
 wire [1:0] owner;wire busy,snoop,lock_grant;wire [31:0] snoop_addr;
 wire [1:0] irq;
 reg active,write_op,aw_sent,w_sent,ar_sent;
 reg [31:0] address,wdata;
 always_comb begin
  masters[0]='0;
  masters[0].aw.addr={32'b0,address};masters[0].aw.size=2;masters[0].aw.burst=1;
  masters[0].ar=masters[0].aw;
  masters[0].w.data=wdata;masters[0].w.strb=15;masters[0].w.last=1;
  masters[0].awvalid=active&&write_op&&!aw_sent;
  masters[0].wvalid=active&&write_op&&!w_sent;
  masters[0].bready=active&&write_op;
  masters[0].arvalid=active&&!write_op&&!ar_sent;
  masters[0].rready=active&&!write_op;
  for(int n=0;n<LITE_PORTS;n++)lite_reply[n]='0;
  for(int n=0;n<3;n++)begin
   masters[n+1]=dma[n];dma_reply[n]=replies[n+1];
   controls[n]=lite[n+1];lite_reply[n+1]=control_replies[n];
  end
 end
 always @(posedge clk)begin
  control_done<=0;
  if(!reset_n)begin active<=0;control_error<=0;control_rdata<=0;write_op<=0;address<=0;wdata<=0;aw_sent<=0;w_sent<=0;ar_sent<=0;end
  else begin
   if(!active&&control_valid)begin
    active<=1;write_op<=control_write;address<=control_address;wdata<=control_wdata;
    aw_sent<=0;w_sent<=0;ar_sent<=0;control_error<=0;
   end
   if(masters[0].awvalid&&replies[0].awready)aw_sent<=1;
   if(masters[0].wvalid&&replies[0].wready)w_sent<=1;
   if(masters[0].arvalid&&replies[0].arready)ar_sent<=1;
   if(masters[0].bready&&replies[0].bvalid)begin active<=0;control_done<=1;control_error<=replies[0].b.resp!=0;end
   if(masters[0].rready&&replies[0].rvalid)begin active<=0;control_done<=1;control_error<=replies[0].r.resp!=0;control_rdata<=replies[0].r.data;end
  end
 end
 or_bo_axi_fabric fabric(.clk,.reset_n,.masters,.replies,.memory,.memory_reply,.lite,.lite_reply,
  .lock_request(1'b0),.lock_grant,.snoop_valid(snoop),.snoop_address(snoop_addr),.snoop_ready(1'b1),.active_master(owner),.busy);
 or_bo_bosio_axi cores(.clk,.reset_n,.control(controls),.control_reply(control_replies),.dma,.dma_reply,
  .sensor_enable(1'b0),.sensor_ready(),.sensor_error(),.projection_irq(irq),
  .video_ready,.video_data,.video_valid,.video_sof,.video_eol,
  .reference_iic_scl_i(1'b1),.reference_iic_sda_i(1'b1),
  .reference_iic_scl_o(),.reference_iic_scl_t(),.reference_iic_sda_o(),.reference_iic_sda_t());
 /* Test host stages coherent CPU buffers; hardware results are written only through AXI. */
 bo_driver_ram #(.WORDS(4194304)) ram(.clk,.reset_n,.req(memory),.rsp(memory_reply),.mem_we,.mem_index,.mem_wdata,.mem_rdata);
 assign active_scene=cores.output0.cache_active_base;
 always @(posedge clk)begin
  if(!reset_n)begin writes0<=0;writes1<=0;reads_out<=0;end
  else begin
   if(memory.wvalid&&memory_reply.wready)begin
    if(owner==1)writes0<=writes0+1;
    if(owner==2)writes1<=writes1+1;
   end
   if(owner==3&&memory_reply.rvalid&&memory.rready)reads_out<=reads_out+1;
  end
 end
endmodule
