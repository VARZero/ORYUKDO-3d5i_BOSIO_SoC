`timescale 1ns/1ps
module tb_pose_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enable=0,sensor_active=1;
 reg [31:0] packet_count=0;
 reg signed [31:0] yaw_mrad=0,pitch_mrad=0,roll_mrad=0;
 reg [3:0] display_transform=0;
 wire [1:0] we,commit,busy;wire [7:0] idx[2];wire signed [31:0] data[2];wire [31:0] applied[2];
 baseline_sensor_pose reference_pose(.clk,.rst_n,.enable,.sensor_active,.packet_count,.yaw_mrad,.pitch_mrad,.roll_mrad,
  .display_transform,.commit_ack(commit[0]),.cfg_we(we[0]),.cfg_idx(idx[0]),.cfg_data(data[0]),.commit(commit[0]),.busy(busy[0]),.applied_count(applied[0]));
 bosio_v2_sensor_pose dut(.clk,.rst_n,.enable,.sensor_active,.packet_count,.yaw_mrad,.pitch_mrad,.roll_mrad,
  .display_transform,.commit_ack(commit[1]),.cfg_we(we[1]),.cfg_idx(idx[1]),.cfg_data(data[1]),.commit(commit[1]),.busy(busy[1]),.applied_count(applied[1]));
 reg [31:0] coeff[2][180];integer count[2]='{0,0};integer checks=0,cycles=0;
 always @(posedge clk)begin
  cycles++;
  if(cycles>1000000)$fatal(1,"pose timeout");
  for(int j=0;j<2;j++)if(rst_n && we[j])begin
   assert(idx[j]==count[j])else $fatal(1,"coefficient ordering lane=%d",j);
   coeff[j][idx[j]]=data[j];count[j]++;
  end
 end
 initial begin
  repeat(30)@(negedge clk);rst_n=1;enable=1;
  for(int n=1;n<=32;n++)begin
   @(negedge clk);count[0]=0;count[1]=0;packet_count=n;display_transform=4'(n);
   yaw_mrad=(n*977)%6280-3140;pitch_mrad=(n*337)%3100-1550;roll_mrad=(n*677)%6280-3140;
   while(applied[0]!=n || applied[1]!=n)@(negedge clk);
   assert(count[0]==180 && count[1]==180)else $fatal(1,"incomplete coefficients");
   for(int k=0;k<180;k++)begin
    assert(coeff[0][k]===coeff[1][k])else $fatal(1,"pose=%d coefficient=%d got=%h expected=%h",n,k,coeff[1][k],coeff[0][k]);
    checks++;
   end
  end
  $display("PASS POSE_EQUIVALENCE poses=32 coefficients=%0d cycles=%0d",checks,cycles);$finish;
 end
endmodule
