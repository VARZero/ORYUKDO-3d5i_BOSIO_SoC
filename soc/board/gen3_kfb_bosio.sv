`timescale 1ns/1ps
// PZ-A7200T-KFB: the SD loader exclusively owns DDR until verified handoff.
// Thereafter the SoC and display share native MIG commands and tagged reads.
module gen3_kfb_bosio(
 input wire sys_clk_p,sys_clk_n,rst_n,uart_rx,output wire uart_tx,error,
 output wire sd_dclk,sd_ncs,sd_mosi,input wire sd_miso,
 input wire gp_uart_rx,output wire gp_uart_tx,
 input wire gp_spi_miso,output wire gp_spi_sck,gp_spi_mosi,gp_spi_cs_n,
 inout wire gp_i2c_scl,gp_i2c_sda,sensor_scl,sensor_sda,
 output wire hdmi_clk_p,hdmi_clk_n,output wire [2:0] hdmi_data_p,hdmi_data_n,
 output wire hdmi_out_en,
 inout wire [31:0] ddr3_dq,inout wire [3:0] ddr3_dqs_p,ddr3_dqs_n,
 output wire [14:0] ddr3_addr,output wire [2:0] ddr3_ba,output wire [3:0] ddr3_dm,
 output wire ddr3_ras_n,ddr3_cas_n,ddr3_we_n,ddr3_reset_n,
 output wire [0:0] ddr3_ck_p,ddr3_ck_n,ddr3_cke,ddr3_cs_n,ddr3_odt
);
 import or_bo_axi_pkg::*;
 wire sysclk,ui_clk,ui_rst,calib,cpu_clk,cpu_raw,cpu_fb,cpu_fb_buf,cpu_locked;
 wire pixel_clk,pixel_raw,serial_clk,serial_raw,video_fb,video_fb_buf,video_locked;
 IBUFDS sysbuf(.I(sys_clk_p),.IB(sys_clk_n),.O(sysclk));
 MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(10.0),
  .CLKOUT0_DIVIDE_F(20.0)) cpu_mmcm(.CLKIN1(ui_clk),.RST(ui_rst),.PWRDWN(1'b0),
  .CLKFBIN(cpu_fb_buf),.CLKFBOUT(cpu_fb),.CLKOUT0(cpu_raw),.LOCKED(cpu_locked));
 BUFG cpu_feedback(.I(cpu_fb),.O(cpu_fb_buf));
 BUFG cpu_buffer(.I(cpu_raw),.O(cpu_clk));
 // 100 MHz / 5 * 37.125 = 742.5 MHz VCO; 74.25 MHz pixels, 371.25 MHz DDR serializer.
 MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.DIVCLK_DIVIDE(5),.CLKFBOUT_MULT_F(37.125),
  .CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(2)) video_mmcm(.CLKIN1(ui_clk),.RST(ui_rst),.PWRDWN(1'b0),
  .CLKFBIN(video_fb_buf),.CLKFBOUT(video_fb),.CLKOUT0(pixel_raw),.CLKOUT1(serial_raw),.LOCKED(video_locked));
 BUFG video_feedback(.I(video_fb),.O(video_fb_buf));
 BUFG pixel_buffer(.I(pixel_raw),.O(pixel_clk));
 BUFG serial_buffer(.I(serial_raw),.O(serial_clk));
 wire done,bad,app_rdy,app_wdf_rdy,rd_valid,rd_end;
 wire [255:0] rd_data,boot_data,native_data;
 wire [28:0] boot_addr,native_addr;
 wire [31:0] native_mask;wire [2:0] native_cmd;
 wire boot_en,boot_wr,boot_wen,native_en,native_wen,native_end;
 assign error=bad;
 sd_boot boot(.sd_dclk,.sd_ncs,.sd_mosi,.sd_miso,.clk(ui_clk),.reset(ui_rst),.calibrated(calib),.app_rdy,.app_wdf_rdy,
  .rd_valid(rd_valid && rd_end && !done),.rd_data,.en(boot_en),.write_cmd(boot_wr),.wdf_en(boot_wen),
  .addr(boot_addr),.wdata(boot_data),.done,.failed(bad));
 // All request owners share one reset event. Reset assertion is asynchronous;
 // each clock domain releases through its local AMD reset synchronizer.
 wire release_system=rst_n && !ui_rst && calib && done && cpu_locked && video_locked;
 wire ui_reset_n;
 // Data-plane gates must change on ui_clk, including reset assertion. Feeding
 // the asynchronous reset stage into response VALID reaches downstream BRAM WE.
 logic run_ui=1'b0;
 always_ff @(posedge ui_clk) run_ui<=ui_reset_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) ui_release(
  .src_arst(release_system),.dest_clk(ui_clk),.dest_arst(ui_reset_n));
 mig_7series_0 ddr(.ddr3_dq,.ddr3_addr,.ddr3_ba,.ddr3_dqs_n,.ddr3_dqs_p,.ddr3_dm,
  .ddr3_ras_n,.ddr3_cas_n,.ddr3_we_n,.ddr3_reset_n,.ddr3_ck_p,.ddr3_ck_n,.ddr3_cke,.ddr3_cs_n,.ddr3_odt,
  .sys_clk_i(sysclk),.sys_rst(rst_n),.ui_clk,.ui_clk_sync_rst(ui_rst),.init_calib_complete(calib),
  .app_addr(done?native_addr:boot_addr),.app_cmd(done?native_cmd:(boot_wr?3'b000:3'b001)),
  .app_en(done?native_en:boot_en),.app_rdy,.app_wdf_wren(done?native_wen:boot_wen),
  .app_wdf_end(done?native_end:boot_wen),.app_wdf_data(done?native_data:boot_data),
  .app_wdf_mask(done?native_mask:32'b0),.app_wdf_rdy,.app_rd_data(rd_data),
  .app_rd_data_valid(rd_valid),.app_rd_data_end(rd_end),.app_sr_req(1'b0),.app_ref_req(1'b0),
  .app_zq_req(1'b0),.app_sr_active(),.app_ref_ack(),.app_zq_ack());
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
  .trap(),.retire(),.trap_pc(),.retire_pc(),.trap_cause());
 IOBUF gp_scl_buf(.IO(gp_i2c_scl),.I(gp_scl_o),.T(gp_scl_t),.O(gp_scl_i));
 IOBUF gp_sda_buf(.IO(gp_i2c_sda),.I(gp_sda_o),.T(gp_sda_t),.O(gp_sda_i));
 IOBUF sensor_scl_buf(.IO(sensor_scl),.I(ref_scl_o),.T(ref_scl_t),.O(ref_scl_pin));
 IOBUF sensor_sda_buf(.IO(sensor_sda),.I(ref_sda_o),.T(ref_sda_t),.O(ref_sda_pin));
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
 assign hdmi_out_en=1'b0; // HDMI2 U6 output-enable is active low.
 kfb_hdmi hdmi_output(.pixel_clk,.serial_clk,.reset_n(pixel_reset_n),.rgb,.de,.hsync,.vsync,
  .clock_p(hdmi_clk_p),.clock_n(hdmi_clk_n),.data_p(hdmi_data_p),.data_n(hdmi_data_n));
endmodule
