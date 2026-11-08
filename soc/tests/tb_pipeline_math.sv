`timescale 1ns/1ps
module tb_pipeline_math;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,iv=0;
 reg signed [32:0] a=0,b=0;
 wire ov;wire signed [65:0] product;
 gen3_mul33_pipe dut(.*);
 reg ce=0;reg [7:0] na=0;reg [24:0] nb=0;wire [31:0] np;
 bosio_projector_mul_mul_8ns_25ns_32_4_1_DSP48_0 narrow(.clk,.rst(!reset_n),.ce,.a(na),.b(nb),.p(np));
 reg [31:0] narrow_expected[0:2];integer narrow_age=0;
 reg signed [65:0] expected[$];
 reg signed [65:0] expected_word;
 reg [31:0] rng=32'h12345678;
 integer sent=0,received=0,cancelled=0,narrow_checks=0,seed=1;
 function automatic [31:0] step(input [31:0] x);return {x[30:0],x[31]^x[21]^x[1]^x[0]};endfunction
 always @(posedge clk)begin
  if(!reset_n)begin cancelled+=expected.size();expected.delete();end
  else if(iv)begin expected.push_back(66'(a)*66'(b));sent++;end
  if(ce)begin
   narrow_expected[2]=narrow_expected[1];narrow_expected[1]=narrow_expected[0];
   narrow_expected[0]=32'(na)*32'(nb);narrow_age++;
  end
  #0.01;
  if(reset_n && ov)begin
   assert(expected.size()>0)else $fatal(1,"phantom product");
   expected_word=expected.pop_front();
   assert(product===expected_word)else $fatal(1,"wide product mismatch got=%h expected=%h",product,expected_word);received++;
  end
  if(narrow_age>=3)begin
   assert(np===narrow_expected[2])else $fatal(1,"narrow product/CE mismatch");narrow_checks++;
  end
 end
 initial begin
  if($value$plusargs("seed=%d",seed))rng^=32'(seed);
  for(int n=0;n<24000;n++)begin
   @(negedge clk);
   rng=step(rng);a=$signed({rng[5],rng});
   rng=step(rng);b=$signed({rng[9],rng});
   case(n%31)
    0:begin a=0;b=-1;end
    1:begin a=-33'sd4294967296;b=-33'sd4294967296;end
    2:begin a=33'sd4294967295;b=33'sd4294967295;end
    3:begin a=-33'sd4294967296;b=33'sd4294967295;end
    default:begin end
   endcase
   reset_n=n>30 && n%509>2;iv=rng[2:0]!=0;ce=rng[7:6]!=0;
   na=rng[15:8];rng=step(rng);nb=rng[24:0];
  end
  @(negedge clk);iv=0;reset_n=1;
  repeat(8)@(negedge clk);
  assert(expected.size()==0 && sent==received+cancelled)else $fatal(1,"product accounting");
  $display("PASS PIPELINE_MATH seed=%0d sent=%0d received=%0d cancelled=%0d narrow_checks=%0d",seed,sent,received,cancelled,narrow_checks);$finish;
 end
endmodule
