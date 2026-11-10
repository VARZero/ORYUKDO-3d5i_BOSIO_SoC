`timescale 1ns/1ps
// Integration backend: production AXI bridge and arbiter, behavioral MIG storage.
module kfb_axi_ram_model(input wire clk,reset_n,
 input or_bo_axi_pkg::ax_req_t req,output or_bo_axi_pkg::ax_rsp_t rsp);
 wire [1:0] req_valid,req_write,req_ready,rsp_valid;
 wire [28:0] req_addr[2];wire [255:0] req_data[2],rsp_data;wire [31:0] req_mask[2];
 wire app_en,app_rdy,app_wdf_wren,app_wdf_end,app_wdf_rdy,app_rd_data_valid,app_rd_data_end;
 wire [2:0] app_cmd;wire [28:0] app_addr;wire [255:0] app_wdf_data,app_rd_data;wire [31:0] app_wdf_mask;
 assign req_valid[1]=0;assign req_write[1]=0;assign req_addr[1]=0;assign req_data[1]=0;assign req_mask[1]='1;
 kfb_axi_mig bridge(.clk,.reset_n,.req,.rsp,.native_valid(req_valid[0]),.native_write(req_write[0]),
  .native_ready(req_ready[0]),.native_addr(req_addr[0]),.native_data(req_data[0]),.native_mask(req_mask[0]),
  .native_rvalid(rsp_valid[0]),.native_rdata(rsp_data));
 kfb_native_arbiter arb(.*);
 kfb_native_ram_model backend(.pause(1'b0),.*);
endmodule
