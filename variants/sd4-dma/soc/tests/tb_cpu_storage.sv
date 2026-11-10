`timescale 1ns/1ps
module tb_cpu_storage(input wire cpu_clk,fabric_clk,reset_n,
 output wire sd_clk,sd_cmd_o,sd_cmd_t,input wire sd_cmd_i,
 output wire [3:0] sd_dat_o,sd_dat_t,input wire [3:0] sd_dat_i);
 import or_bo_axi_pkg::*;
 ax_req_t memory,storage_memory;ax_rsp_t memory_reply,storage_reply;
 al_req_t sd_req,dma_req;al_rsp_t sd_rsp,dma_rsp;
 wire dma_irq,sd_irq,trap,retire,boot_ready,boot_failed;reg ready_for_cpu=0;
 wire [31:0] trap_pc,retire_pc;wire [4:0] trap_cause;
 // This integration fixture tests initialization and CPU runtime access; the
 // raw image loader has a separate actual-image CRC/readback regression.
 always @(posedge fabric_clk) if(!reset_n)ready_for_cpu<=0;else if(boot_ready)ready_for_cpu<=1;
 wire soc_reset_n=reset_n && ready_for_cpu;
 gen3_bosio_soc dut(.cpu_clk,.fabric_clk,.reset_n(soc_reset_n),.uart_rx(1'b1),.uart_tx(),
  .storage_memory,.storage_reply,.sd_req,.sd_rsp,.dma_req,.dma_rsp,.sd_irq,.dma_irq,
  .memory,.memory_reply,.gp_uart_rx(1'b1),.gp_uart_tx(),.gp_spi_miso(1'b1),
  .gp_spi_mosi(),.gp_spi_sck(),.gp_spi_cs_n(),.gp_i2c_scl_i(1'b1),.gp_i2c_sda_i(1'b1),
  .gp_i2c_scl_o(),.gp_i2c_scl_t(),.gp_i2c_sda_o(),.gp_i2c_sda_t(),
  .video_ready(1'b1),.video_data(),.video_valid(),.video_sof(),.video_eol(),
  .reference_iic_scl_i(1'b1),.reference_iic_sda_i(1'b1),
  .reference_iic_scl_o(),.reference_iic_scl_t(),.reference_iic_sda_o(),.reference_iic_sda_t(),
  .trap,.retire,.trap_pc,.retire_pc,.trap_cause);
 or_sd_storage storage(.clk(fabric_clk),.reset_n,.boot_done(ready_for_cpu),.boot_enable(1'b1),
  .boot_request(1'b0),.boot_lba(32'b0),.boot_ready,.boot_valid(),.boot_data(),.boot_take(1'b0),
  .boot_complete(),.boot_failed,.sd_req,.dma_req,.sd_rsp,.dma_rsp,
  .memory(storage_memory),.reply(storage_reply),.sd_irq,.dma_irq,
  .sd_clk,.sd_cmd_o,.sd_cmd_t,.sd_cmd_i,.sd_dat_o,.sd_dat_t,.sd_dat_i);
 `ifdef KFB_NATIVE_BACKEND
 `define STORAGE_TEST_MEMORY ram.backend.mem
 kfb_axi_ram_model ram(.clk(fabric_clk),.reset_n,.req(memory),.rsp(memory_reply));
 `else
 `define STORAGE_TEST_MEMORY ram.mem
 axi_ram_model ram(.clk(fabric_clk),.reset_n,.req(memory),.rsp(memory_reply));
 `endif
 int cycles=0,retired=0,m_traps=0,s_traps=0,snoops=0;
 always @(posedge cpu_clk) if(reset_n) begin
  cycles<=cycles+1;
  assert(!boot_failed)else $fatal(1,"Card initialization failed");
  if(retire)retired<=retired+1;
  if(dut.invalidate)snoops<=snoops+1;
  if(trap)begin
   if(!dut.soc.trap_interrupt || !(trap_cause==11 || trap_cause==9))
    $fatal(1,"Unexpected CPU trap pc=%h cause=%d interrupt=%b",trap_pc,trap_cause,dut.soc.trap_interrupt);
   if(trap_cause==11)m_traps<=m_traps+1;else s_traps<=s_traps+1;
  end
  if(`STORAGE_TEST_MEMORY['h7ff00/4][31:16]==16'hbad0)$fatal(1,"CPU storage firmware failed %h",`STORAGE_TEST_MEMORY['h7ff00/4]);
  if(`STORAGE_TEST_MEMORY['h7ff00/4]==32'h600d0004)begin
   assert(m_traps>=4 && s_traps>0 && snoops>=384)else $fatal(1,"Missing IRQ/snoop coverage");
   $display("PASS CPU SD read/write/roundtrip, DMA MMIO copy/fill payloads, PLIC M/S claim/complete, CDC, precise external interrupts cycles=%0d retired=%0d M=%0d S=%0d snoops=%0d",cycles,retired,m_traps,s_traps,snoops);
   `ifdef KFB_NATIVE_BACKEND
   assert(m_traps>=5 && s_traps>=2 && snoops>=576)else $fatal(1,"Missing upper DDR coverage");
   $display("PASS production AXI-MIG bridge/native arbiter with mock DDR, SD DMA at 0xbffff000 and fill through 0xbffffffc");
   `endif
   $finish;
  end
  if(cycles>2000000)$fatal(1,"CPU storage timeout pc=%h",retire_pc);
 end
 `undef STORAGE_TEST_MEMORY
endmodule
