`timescale 1ns/1ps
module tb_projector_banks;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enable=0,ready=0,frame_ready=0,cfg_we=0,commit=0,scene_valid=1,scene_pending=0;
 reg [7:0] cfg_idx=0;reg [31:0] cfg_data=0;reg [1:0] resolution=1;
 wire commit_ack,frame_start,valid;wire [4:0] face;wire [31:0] n0,n2,den;wire [1:0] cell_resolution;
 bosio_v2_projector dut(.*);
 reg [31:0] expected[180];integer checks=0;
 initial begin
  repeat(25)@(negedge clk);rst_n=1;enable=1;
  for(int n=0;n<180;n++)begin
   cfg_we=1;cfg_idx=8'(n);cfg_data=32'h23450000+32'(n);expected[n]=cfg_data;
   @(negedge clk);
  end
  // Commit immediately after the final write enters its local bank.
  cfg_we=0;enable=1;frame_ready=1;commit=1;
  #0.01;
  assert(!frame_start)else $fatal(1,"commit bypassed pending bank write");
  @(negedge clk);
  assert(frame_start)else $fatal(1,"commit did not resume after drain");
  for(int n=0;n<180;n++)begin assert(dut.shadow[n]===expected[n])else $fatal(1,"bank write %d",n);checks++;end
  @(negedge clk);assert(commit_ack)else $fatal(1,"missing commit ack");commit=0;enable=0;frame_ready=0;
  repeat(3)@(negedge clk);
  cfg_we=1;cfg_idx=179;cfg_data=32'hdeadbeef;
  @(negedge clk);cfg_we=0;rst_n=0;
  @(negedge clk);rst_n=1;
  repeat(3)@(negedge clk);
  assert(dut.shadow[179]===expected[179])else $fatal(1,"reset failed to cancel staged write");checks++;
  $display("PASS PROJECTOR_BANKS checks=%0d",checks);$finish;
 end
endmodule
