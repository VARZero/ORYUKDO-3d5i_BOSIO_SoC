`timescale 1ns/1ps
// Rotate clockwise, then reflect in OUTPUT screen axes, around pixel center.
// Input is ordered (start, dx, dy) triples, at most one word per clock.
// Pipeline throughput is one triple per three clocks; no pixel-rate hardware.
// Native 1280x720 timing and sample pitch are preserved. Quarter turns expose
// a centered 720x1280 logical viewport, rather than stretching a stored frame.
module bosio_display_transform(
 input wire clk,rst_n,
 input wire [3:0] requested, // [1:0] quarter turns; [2] flip X; [3] flip Y
 input wire cfg_we,input wire [7:0] cfg_idx,input wire [31:0] cfg_data,
 input wire commit,input wire commit_ack,
 output reg out_we,output reg [7:0] out_idx,output reg [31:0] out_data,
 output wire out_commit,output reg [3:0] active
);
 reg [3:0] captured;
 reg signed [31:0] raw_start,raw_dx;
 reg signed [31:0] turn_dx,turn_dy;
 wire signed [31:0] raw_dy=$signed(cfg_data);
 always @* begin
  case(captured[1:0])
   0:begin turn_dx=raw_dx;turn_dy=raw_dy;end
   1:begin turn_dx=-raw_dy;turn_dy=raw_dx;end
   2:begin turn_dx=-raw_dx;turn_dy=-raw_dy;end
   default:begin turn_dx=raw_dy;turn_dy=-raw_dx;end
  endcase
  if(captured[2])turn_dx=-turn_dx;
  if(captured[3])turn_dy=-turn_dy;
 end
 reg v0,v1,v2;
 reg [7:0] idx0,idx1,idx2;
 reg signed [31:0] start0,start1,start2,dx0,dx1,dx2,dy0,dy1,dy2;
 reg signed [32:0] diff_x,diff_y;
 (* use_dsp="no" *) reg signed [63:0] prod_x,prod_y;
 reg signed [63:0] correction;
 reg [1:0] phase;
 reg [7:0] emit_idx;
 reg [31:0] emit_dx,emit_dy;
 assign out_commit=commit && !(v0||v1||v2||(phase!=0)||out_we);
 always @(posedge clk)begin
  if(!rst_n)begin
   captured<=0;active<=0;v0<=0;v1<=0;v2<=0;phase<=0;
   out_we<=0;out_idx<=0;out_data<=0;raw_start<=0;raw_dx<=0;
  end else begin
   out_we<=0;v0<=0;v1<=v0;v2<=v1;
   if(commit_ack)active<=captured;
   if(cfg_we && cfg_idx<180)begin
    if(cfg_idx==0)captured<=requested;
    case(cfg_idx%3)
     0:raw_start<=cfg_data;
     1:raw_dx<=cfg_data;
     2:begin
      v0<=1;idx0<=cfg_idx-2;start0<=raw_start;dx0<=turn_dx;dy0<=turn_dy;
      diff_x<=$signed({raw_dx[31],raw_dx})-$signed({turn_dx[31],turn_dx});
      diff_y<=$signed({raw_dy[31],raw_dy})-$signed({turn_dy[31],turn_dy});
     end
    endcase
   end
   if(v0)begin
    prod_x<=diff_x*33'sd1279;prod_y<=diff_y*33'sd719;
    idx1<=idx0;start1<=start0;dx1<=dx0;dy1<=dy0;
   end
   if(v1)begin
    correction<=prod_x+prod_y;
    idx2<=idx1;start2<=start1;dx2<=dx1;dy2<=dy1;
   end
   if(v2)begin
    out_we<=1;out_idx<=idx2;out_data<=$signed(start2)+(correction>>>1);
    emit_idx<=idx2;emit_dx<=dx2;emit_dy<=dy2;phase<=1;
   end else if(phase==1)begin
    out_we<=1;out_idx<=emit_idx+1;out_data<=emit_dx;phase<=2;
   end else if(phase==2)begin
    out_we<=1;out_idx<=emit_idx+2;out_data<=emit_dy;phase<=0;
   end
  end
 end
endmodule
