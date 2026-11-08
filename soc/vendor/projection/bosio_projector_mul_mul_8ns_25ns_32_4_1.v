
`timescale 1 ns / 1 ps

  module bosio_projector_mul_mul_8ns_25ns_32_4_1_DSP48_0(clk, rst, ce, a, b, p);
input clk;
input rst;
input ce;
input [8 - 1 : 0] a;
input [25 - 1 : 0] b;
output signed [32 - 1 : 0] p;

reg signed [32 - 1 : 0] p_reg; 

reg [8 - 1 : 0] a_reg; 
reg [25 - 1 : 0] b_reg; 

reg signed [32 - 1 : 0] p_reg_tmp;
reg [7:0] high_product; 

always @ (posedge clk) begin
    if (ce) begin
        a_reg <= a;
        b_reg <= b;
        p_reg_tmp <= $signed({1'b0, a_reg}) * $signed({1'b0, b_reg[23:0]});
        high_product <= b_reg[24] ? a_reg : 8'b0;
        p_reg <= p_reg_tmp + {high_product,24'b0};
    end
end

assign p = p_reg;

endmodule
`timescale 1 ns / 1 ps
module bosio_projector_mul_mul_8ns_25ns_32_4_1(
    clk,
    reset,
    ce,
    din0,
    din1,
    dout);

parameter ID = 32'd1;
parameter NUM_STAGE = 32'd1;
parameter din0_WIDTH = 32'd1;
parameter din1_WIDTH = 32'd1;
parameter dout_WIDTH = 32'd1;
input clk;
input reset;
input ce;
input[din0_WIDTH - 1:0] din0;
input[din1_WIDTH - 1:0] din1;
output[dout_WIDTH - 1:0] dout;



bosio_projector_mul_mul_8ns_25ns_32_4_1_DSP48_0 bosio_projector_mul_mul_8ns_25ns_32_4_1_DSP48_0_U(
    .clk( clk ),
    .rst( reset ),
    .ce( ce ),
    .a( din0 ),
    .b( din1 ),
    .p( dout ));

endmodule

