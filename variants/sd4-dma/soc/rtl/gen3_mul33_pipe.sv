`timescale 1ns/1ps
// Four-stage signed 33x33 product. Every 17x17 partial product has input,
// multiplier and output registers for DSP AREG/BREG/MREG/PREG packing.
// Data registers are unreset; reset/flush cancels the valid pipeline.
module gen3_mul33_pipe(
 input wire clk,reset_n,iv,
 input wire signed [32:0] a,b,
 output wire ov,output reg signed [65:0] product
);
 reg [3:0] valid;
 reg signed [16:0] al,ah,bl,bh;
 (* use_dsp="yes" *) reg signed [33:0] m00,m01,m10,m11;
 (* shreg_extract="no" *) reg signed [33:0] p00,p01,p10,p11;
 always @(posedge clk)begin
  if(!reset_n)valid<=0;else valid<={valid[2:0],iv};
  al<=$signed({1'b0,a[15:0]});ah<=a[32:16];
  bl<=$signed({1'b0,b[15:0]});bh<=b[32:16];
  m00<=al*bl;m01<=al*bh;m10<=ah*bl;m11<=ah*bh;
  p00<=m00;p01<=m01;p10<=m10;p11<=m11;
  product<=$signed({{32{p00[33]}},p00})+
           ($signed({{32{p01[33]}},p01})<<<16)+
           ($signed({{32{p10[33]}},p10})<<<16)+
           ($signed({{32{p11[33]}},p11})<<<32);
 end
 assign ov=valid[3];
endmodule
