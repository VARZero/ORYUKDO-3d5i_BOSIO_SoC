`timescale 1ns/1ps
// Board adapter only. The Digilent rgb2dvi source files are byte-identical
// to the pinned official distribution; no internal IP edits are applied.
module kfb_hdmi(
 input wire pixel_clk,serial_clk,reset_n,
 input wire [23:0] rgb,input wire de,hsync,vsync,
 output wire clock_p,clock_n,output wire [2:0] data_p,data_n
);
 // reset_n is the shared, board-level pixel-domain reset. Scanout and
 // HDMI use one crossing, rather than independently releasing one domain.
 // The IP's documented reset input receives a pixel-domain reset. Keep
 // active video blank through its reset release and encoder pipeline fill.
 logic pixel_run=0;
 logic [3:0] video_enable=0;
 always_ff @(posedge pixel_clk)begin
  pixel_run<=reset_n;
  if(!reset_n)video_enable<=0;
  else video_enable<={video_enable[2:0],pixel_run};
 end
 // Digilent's vid_pData port is RBG, whereas the BOSIO stream is RGB.
 rgb2dvi #(.kGenerateSerialClk(1'b0),.kRstActiveHigh(1'b1)) transmitter(
  .PixelClk(pixel_clk),.SerialClk(serial_clk),.aRst(!pixel_run),.aRst_n(1'b1),
  .vid_pData({rgb[23:16],rgb[7:0],rgb[15:8]}),
  .vid_pVDE(de && video_enable[3]),.vid_pHSync(hsync),.vid_pVSync(vsync),
  .TMDS_Clk_p(clock_p),.TMDS_Clk_n(clock_n),.TMDS_Data_p(data_p),.TMDS_Data_n(data_n));
endmodule
