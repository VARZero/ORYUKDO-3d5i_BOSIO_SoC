`timescale 1ns/1ps
module tb_muldiv_equivalence;
 import rv32_pkg::*;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,flush=0,valid=0,result_ready=0;
 reg [7:0] uop=U_MUL;
 reg [31:0] a=0,b=0;
 wire [1:0] ready,result_valid;wire [31:0] result[2];
 baseline_muldiv reference_md(.clk,.reset_n,.flush,.valid,.result_ready,.uop,.a,.b,
  .ready(ready[0]),.result_valid(result_valid[0]),.result(result[0]));
 rv32_muldiv dut(.clk,.reset_n,.flush,.valid,.result_ready,.uop,.a,.b,
  .ready(ready[1]),.result_valid(result_valid[1]),.result(result[1]));
 reg [31:0] rng=32'h13579bdf,held;
 reg [7:0] ops[8]='{U_MUL,U_MULH,U_MULHSU,U_MULHU,U_DIV,U_DIVU,U_REM,U_REMU};
 integer checks=0,cancels=0,cycles=0,seed=1;
 function automatic [31:0] step(input [31:0] x);return {x[30:0],x[31]^x[21]^x[1]^x[0]};endfunction
 always @(posedge clk)begin cycles++;if(cycles>300000)$fatal(1,"muldiv timeout");end
 initial begin
  if($value$plusargs("seed=%d",seed))rng^=32'(seed);
  repeat(25)@(negedge clk);reset_n=1;
  for(int n=0;n<1600;n++)begin
   while(ready!=2'b11)@(negedge clk);
   rng=step(rng);a=rng;rng=step(rng);b=rng;uop=ops[n%8];
   case((n/8)%17)
    0:b=0;
    1:begin a=32'h80000000;b=32'hffffffff;end
    2:begin a=32'hffffffff;b=32'hffffffff;end
    3:begin a=32'h80000000;b=32'h80000000;end
    4:begin a=0;b=32'h80000000;end
    default:begin end
   endcase
   valid=1;@(negedge clk);valid=0;
   while(result_valid!=2'b11)@(negedge clk);
   assert(result[0]===result[1])else $fatal(1,"muldiv op=%h a=%h b=%h expected=%h got=%h",uop,a,b,result[0],result[1]);
   held=result[1];repeat(3)begin @(negedge clk);assert(result_valid==3 && result[1]===held)else $fatal(1,"result not held");end
   checks++;result_ready=1;@(negedge clk);result_ready=0;
  end
  for(int n=0;n<64;n++)begin
   while(ready!=3)@(negedge clk);
   uop=n[0]?U_DIV:U_MULH;a=32'h87654321;b=32'h81234567;valid=1;
   @(negedge clk);valid=0;
   repeat(n%4)@(negedge clk);
   flush=1;@(negedge clk);flush=0;#0.01;
   assert(result_valid==0 && ready==3)else $fatal(1,"flush did not release lane");
   // Reuse immediately, while the cancelled product's data can still be in
   // flight. An old valid token must not publish as the new operation.
   uop=U_MULH;a=32'hfedcba98;b=32'h71234567;valid=1;
   @(negedge clk);valid=0;
   while(result_valid!=3)@(negedge clk);
   assert(result[0]===result[1])else $fatal(1,"cancelled product contaminated reuse");
   result_ready=1;@(negedge clk);result_ready=0;checks++;
   repeat(8)begin @(negedge clk);assert(result_valid==0)else $fatal(1,"late result after reuse");end
   cancels++;
  end
  $display("PASS MULDIV_EQUIVALENCE seed=%0d checks=%0d flushes=%0d cycles=%0d",seed,checks,cancels,cycles);$finish;
 end
endmodule
