`timescale 1ns/1ps
module tb_slot_function;
 localparam IDX_W=4,PC_W=32,PC_STEP=4;
 reg [31:0] pc=0,base=0;
 function automatic logic [IDX_W-1:0] slot_of(input logic [PC_W-1:0] pc,input logic [PC_W-1:0] base);
 if((PC_STEP&(PC_STEP-1))==0) return IDX_W'(pc/PC_STEP)-IDX_W'(base/PC_STEP);
 return IDX_W'((pc-base)/PC_STEP);
 endfunction
 wire [3:0] result=slot_of(pc,base);
 initial begin #10;pc='h8000013c;base='h80000134;#10;$display("slot=%h expected=2",result);assert(result==2)else $fatal(1,"slot mismatch");$finish;end
endmodule
