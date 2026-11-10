`timescale 1ns/1ps
// Derived board digital boundary. SD loader is a second Verilated RTL object.
// Both models share a continuously maintained native DDR backend; no memory preload.
module tb_kfb_coldboot(
 input wire ui_clk,cpu_clk,pixel_clk,rst_n,ui_rst,calib,clocks_locked,
 input wire boot_done,boot_bad,boot_en,boot_wr,boot_wen,
 input wire [28:0] boot_addr,input wire [255:0] boot_data,
 input wire app_rdy,app_wdf_rdy,rd_valid,rd_end,input wire [255:0] rd_data,
 output wire [28:0] app_addr,output wire [2:0] app_cmd,
 output wire app_en,app_wdf_wren,app_wdf_end,
 output wire [255:0] app_wdf_data,output wire [31:0] app_wdf_mask,
 input wire uart_rx,output wire uart_tx,error,released,
 output wire debug_retire,debug_trap,output wire [31:0] debug_pc,debug_trap_pc,debug_satp,
 output wire [4:0] debug_cause
);
 wire gp_uart_rx=1'b1,gp_spi_miso=1'b1;
 wire gp_uart_tx,gp_spi_sck,gp_spi_mosi,gp_spi_cs_n;
 import or_bo_axi_pkg::*;
 wire done=boot_done,bad=boot_bad;
 wire [255:0] native_data;
 wire [28:0] native_addr;
 wire [31:0] native_mask;wire [2:0] native_cmd;
 wire native_en,native_wen,native_end;
 assign error=bad;
 // All request owners share one reset event. Reset assertion is asynchronous;
 // each clock domain releases through its local AMD reset synchronizer.
 wire release_system=rst_n && !ui_rst && calib && done && clocks_locked;
 wire ui_reset_n;
 // Data-plane gates must change on ui_clk, including reset assertion. Feeding
 // the asynchronous reset stage into response VALID reaches downstream BRAM WE.
 logic run_ui=1'b0;
 always_ff @(posedge ui_clk) run_ui<=ui_reset_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) ui_release(
  .src_arst(release_system),.dest_clk(ui_clk),.dest_arst(ui_reset_n));
 // Same boot/runtime mux as gen3_kfb_bosio; native MIG PHY is modeled in C++.
 assign app_addr=done?native_addr:boot_addr;
 assign app_cmd=done?native_cmd:(boot_wr?3'b000:3'b001);
 assign app_en=done?native_en:boot_en;
 assign app_wdf_wren=done?native_wen:boot_wen;
 assign app_wdf_end=done?native_end:boot_wen;
 assign app_wdf_data=done?native_data:boot_data;
 assign app_wdf_mask=done?native_mask:32'b0;
 ax_req_t memory;ax_rsp_t memory_reply;
 wire [1:0] req_valid,req_write,req_ready,rsp_valid;
 wire [28:0] req_addr[2];wire [255:0] req_data[2],rsp_data;wire [31:0] req_mask[2];
 kfb_native_arbiter arb(.clk(ui_clk),.reset_n(run_ui),.req_valid,.req_write,.req_ready,.req_addr,.req_data,.req_mask,
  .rsp_valid,.rsp_data,.app_en(native_en),.app_cmd(native_cmd),.app_addr(native_addr),.app_rdy,
  .app_wdf_wren(native_wen),.app_wdf_end(native_end),.app_wdf_data(native_data),.app_wdf_mask(native_mask),.app_wdf_rdy,
  .app_rd_data_valid(rd_valid && done),.app_rd_data_end(rd_end),.app_rd_data(rd_data));
 kfb_axi_mig bridge(.clk(ui_clk),.reset_n(run_ui),.req(memory),.rsp(memory_reply),
  .native_valid(req_valid[0]),.native_write(req_write[0]),.native_ready(req_ready[0]),.native_addr(req_addr[0]),
  .native_data(req_data[0]),.native_mask(req_mask[0]),.native_rvalid(rsp_valid[0]),.native_rdata(rsp_data));
 wire video_ready,video_valid,video_sof,video_eol;wire [23:0] video_data,rgb;
 wire hsync,vsync,de,serial_tx;
 wire gp_scl_i,gp_scl_o,gp_scl_t,gp_sda_i,gp_sda_o,gp_sda_t;
 wire ref_scl_i,ref_scl_o,ref_scl_t,ref_sda_i,ref_sda_o,ref_sda_t,ref_scl_pin,ref_sda_pin;
 assign uart_tx=run_ui?serial_tx:1'b1;
 gen3_bosio_soc system(.cpu_clk,.fabric_clk(ui_clk),.reset_n(release_system),.uart_rx,.uart_tx(serial_tx),
  .gp_uart_rx,.gp_uart_tx,.gp_spi_miso,.gp_spi_sck,.gp_spi_mosi,.gp_spi_cs_n,
  .gp_i2c_scl_i(gp_scl_i),.gp_i2c_scl_o(gp_scl_o),.gp_i2c_scl_t(gp_scl_t),
  .gp_i2c_sda_i(gp_sda_i),.gp_i2c_sda_o(gp_sda_o),.gp_i2c_sda_t(gp_sda_t),
  .memory,.memory_reply,.video_ready,.video_data,.video_valid,.video_sof,.video_eol,
  .reference_iic_scl_i(ref_scl_i),.reference_iic_scl_o(ref_scl_o),.reference_iic_scl_t(ref_scl_t),
  .reference_iic_sda_i(ref_sda_i),.reference_iic_sda_o(ref_sda_o),.reference_iic_sda_t(ref_sda_t),
  .trap(debug_trap),.retire(debug_retire),.trap_pc(debug_trap_pc),.retire_pc(debug_pc),.trap_cause(debug_cause));
 assign gp_scl_i=gp_scl_t?1'b1:gp_scl_o;
 assign gp_sda_i=gp_sda_t?1'b1:gp_sda_o;
 assign ref_scl_pin=ref_scl_t?1'b1:ref_scl_o;
 assign ref_sda_pin=ref_sda_t?1'b1:ref_sda_o;
 xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) sensor_clock_input(
  .src_clk(1'b0),.src_in(ref_scl_pin),.dest_clk(ui_clk),.dest_out(ref_scl_i));
 xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) sensor_data_input(
  .src_clk(1'b0),.src_in(ref_sda_pin),.dest_clk(ui_clk),.dest_out(ref_sda_i));
 wire pixel_reset_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) pixel_release(
  .src_arst(run_ui),.dest_clk(pixel_clk),.dest_arst(pixel_reset_n));
 kfb_video display(.clk(ui_clk),.pixel_clk,.reset_n(run_ui),.pixel_reset_n,.video_data,.video_valid,.video_sof,.video_eol,.video_ready,
  .native_valid(req_valid[1]),.native_write(req_write[1]),.native_ready(req_ready[1]),.native_addr(req_addr[1]),
  .native_data(req_data[1]),.native_mask(req_mask[1]),.native_rvalid(rsp_valid[1]),.native_rdata(rsp_data),
  .rgb,.hsync,.vsync,.de,.completed_frames(),.displayed_frames(),.format_errors(),.underflow_sticky());
 // Pixel stream is observed; TMDS/VHDL serializer is outside cold-boot scope.
 assign released=release_system;
 assign debug_satp=system.soc.cpu.satp;
 `define C system.soc.cpu
 integer watchdog=0;
 always @(posedge cpu_clk) begin
  if(!released || debug_retire) watchdog<=0;
  else watchdog<=watchdog+1;
  if(watchdog==20000) begin
   $display("STALL base=%h req=%h barrier=%b tag=%h cs=%0d lsu=%0d kill=%b boundary=%h inc=%b side=%b cursor=%d admitted=%h done=%h checkpoints=%d",`C.base_pc,`C.req_tags[31:0],`C.barrier,`C.barrier_tag,`C.cs,`C.lsu.state,`C.kill_active,`C.boundary,`C.inclusive,`C.effect_req,`C.scheduler.U_CONTROL_PLANE.commit_cursor,`C.scheduler.oldest_admitted,`C.scheduler.oldest_done,`C.scheduler.U_CONTROL_PLANE.branch_count);
   $display("CPU_BUS v/r=%b%b response=%b%b address=%h store=%b ifv/r=%b%b ifrsp=%b%b",`C.mem_valid,`C.mem_ready,`C.mem_response_valid,`C.mem_response_ready,`C.mem_address,`C.mem_store,`C.if_valid,`C.if_ready,`C.if_response_valid,`C.if_response_ready);
   $display("BUS bridge=%0d fabric=%0d mig_bridge=%0d arb_active=%b count=%d req=%b ready=%b",system.bridge.state,system.fabric.state,bridge.state,arb.active,arb.count,req_valid,req_ready);
   $display("LSQ order=%h ready=%h inflight=%b counts=%d/%d issue=%b take=%b wb=%b accepted=%b",`C.scheduler.G_LSQ.U_LSQ.order_head,`C.scheduler.G_LSQ.U_LSQ.upper_head[34:0],`C.scheduler.G_LSQ.U_LSQ.in_flight,`C.scheduler.G_LSQ.U_LSQ.order_count,`C.scheduler.G_LSQ.U_LSQ.upper_count,`C.issue,`C.take,`C.wb,`C.accepted);
   $display("DRAIN all=%b fetch=%b nel=%b",`C.scheduler.all_window_drained,`C.scheduler.fcl_fetch_drained,`C.scheduler.nel_stage2_drained);
   for(integer w=0;w<8;w++) $display("FLOW %d base=%h admitted=%h kill=%h done=%h discarded=%h branchdrained=%b",w,`C.scheduler.U_FLOW_CONTROL_LOGIC.fdu_start[w],`C.scheduler.U_FLOW_CONTROL_LOGIC.fdu_admitted[w],`C.scheduler.U_FLOW_CONTROL_LOGIC.fdu_killed[w],`C.scheduler.U_FLOW_CONTROL_LOGIC.fdu_completed[w],`C.scheduler.U_FLOW_CONTROL_LOGIC.fdu_discarded[w],`C.scheduler.U_FLOW_CONTROL_LOGIC.branch_drained[w]);
   for(integer e=0;e<5;e++) $display("LANE %d pc=%h op=%h rd=%d rs=%d/%d value=%h/%h",e,`C.ex[e].tag,`C.ex[e].op,`C.ex[e].rd,`C.ex[e].rs1,`C.ex[e].rs2,`C.a[e],`C.b[e]);
   $fatal(1,"No CPU retirement for 20000 CPU clocks");
  end
 end
 `undef C
endmodule
