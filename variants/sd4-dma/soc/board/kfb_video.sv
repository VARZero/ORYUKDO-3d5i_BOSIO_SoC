`timescale 1ns/1ps
// RGB888 stream -> double-buffered DDR -> fixed-rate video. Producer stalls
// when both buffers are owned; scanout repeats a complete front buffer.
// A short FIFO cannot guarantee a continuous display from a variable-rate
// renderer. Buffers occupy 0xbf800000..0xbfffffff, reserved in the DTB.
module kfb_video #(
 parameter int WIDTH=1280,HEIGHT=720,H_FRONT=110,H_SYNC=40,H_BACK=220,
 parameter int V_FRONT=5,V_SYNC=5,V_BACK=20,FIFO_DEPTH=512,
 parameter logic [28:0] BASE0=29'h0fe00000,BASE1=29'h0ff00000
)(
 input wire clk,pixel_clk,reset_n,pixel_reset_n,
 input wire [23:0] video_data,input wire video_valid,video_sof,video_eol,output wire video_ready,
 output wire native_valid,native_write,output wire [28:0] native_addr,
 output wire [255:0] native_data,output wire [31:0] native_mask,
 input wire native_ready,native_rvalid,input wire [255:0] native_rdata,
 output wire [23:0] rgb,output wire hsync,vsync,de,
 output logic [31:0] completed_frames,displayed_frames,format_errors,
 output wire underflow_sticky
);
 localparam int PIXELS=WIDTH*HEIGHT,LINES=PIXELS/8;
 localparam int HT=WIDTH+H_FRONT+H_SYNC+H_BACK,VT=HEIGHT+V_FRONT+V_SYNC+V_BACK;
 // pixel_reset_n is supplied by the common board-level pixel reset bridge.
 logic [15:0] px,py;logic frame_toggle,frame_underflow,ever_underflow;
 wire frame_sync;logic frame_seen;
 xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) frame_crossing(
  .src_clk(pixel_clk),.src_in(frame_toggle),.dest_clk(clk),.dest_out(frame_sync));
 xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) underflow_crossing(
  .src_clk(pixel_clk),.src_in(ever_underflow),.dest_clk(clk),.dest_out(underflow_sticky));
 logic front,front_valid,back,frame_pending,collecting,line_full,line_last;
 wire front_valid_pixel;
 xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) valid_crossing(
  .src_clk(clk),.src_in(front_valid),.dest_clk(pixel_clk),.dest_out(front_valid_pixel));
 logic [19:0] pixel_count;logic [15:0] input_x;
 logic [2:0] pack_count,pixel_lane;
 logic [255:0] packed_line;
 logic [16:0] write_index,read_index;
 logic [4:0] pending_reads;
 typedef enum logic [1:0] {RUN,DRAIN,RESET_FIFO,WAIT_FIFO} scan_state_t;
 scan_state_t scan_state;logic [5:0] reset_count;
 logic busy,writing,prefer_write;
 logic [28:0] address;logic [255:0] write_line;
 // The FIFO reset crosses into pixel_clk. Register the state decode so
 // combinational state transitions cannot become asynchronous reset pulses.
 logic fifo_reset_n=0;
 always_ff @(posedge clk) fifo_reset_n<=reset_n && scan_state!=DRAIN && scan_state!=RESET_FIFO;
 wire [$clog2(FIFO_DEPTH):0] fifo_used;
 wire fifo_online,fifo_ready,fifo_valid,fifo_pop;
 wire [255:0] fifo_data;
 kfb_video_fifo #(.WIDTH(256),.DEPTH(FIFO_DEPTH)) scan_fifo(
  .reset_n(fifo_reset_n),.s_clk(clk),.s_reset_n(fifo_reset_n),.d_clk(pixel_clk),.d_reset_n(pixel_reset_n),
  .s_data(native_rdata),.s_valid(native_rvalid && scan_state==RUN),.s_ready(fifo_ready),.used(fifo_used),.online(fifo_online),
  .d_data(fifo_data),.d_valid(fifo_valid),.d_ready(fifo_pop));
 assign native_valid=reset_n && busy;
 assign native_write=writing;assign native_addr=address;
 assign native_data=write_line;assign native_mask=0;
 wire read_candidate=scan_state==RUN && front_valid && read_index<17'(LINES) && pending_reads<8 &&
                     fifo_online && (int'(fifo_used)+int'(pending_reads)<FIFO_DEPTH-4);
 wire write_candidate=scan_state==RUN && line_full;
 // Scanout has a fixed deadline. Throttle the renderer while the display
 // queue is low; round-robin alone cannot guarantee continuous pixels.
 wire select_write=write_candidate && (!read_candidate || (prefer_write && int'(fifo_used)>=FIFO_DEPTH/2));
 wire launch_read=busy && !writing && native_ready;
 wire launch_write=busy && writing && native_ready;
 assign video_ready=reset_n && !frame_pending && !line_full;
 wire pixel_fire=video_valid && video_ready;
 assign de=pixel_reset_n && px<16'(WIDTH) && py<16'(HEIGHT);
 assign hsync=pixel_reset_n && px>=16'(WIDTH+H_FRONT) && px<16'(WIDTH+H_FRONT+H_SYNC);
 assign vsync=pixel_reset_n && py>=16'(HEIGHT+V_FRONT) && py<16'(HEIGHT+V_FRONT+V_SYNC);
 assign rgb=de && front_valid_pixel && !frame_underflow && fifo_valid ? fifo_data[pixel_lane*32+:24]:24'b0;
 assign fifo_pop=de && front_valid_pixel && !frame_underflow && fifo_valid && pixel_lane==7;
 always_ff @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin px<=0;py<=16'(HEIGHT);frame_toggle<=0;frame_underflow<=0;ever_underflow<=0;pixel_lane<=0;end
  else begin
   if(px==16'(HT-1))begin px<=0;py<=py==16'(VT-1)?16'd0:py+1'b1;end else px<=px+1'b1;
   if(px==0 && py==16'(HEIGHT))begin frame_toggle<=!frame_toggle;frame_underflow<=0;pixel_lane<=0;end
   if(de && front_valid_pixel && !frame_underflow)begin
    if(!fifo_valid)begin frame_underflow<=1;ever_underflow<=1;end
    else pixel_lane<=pixel_lane+1'b1;
   end
  end
 end
 always_ff @(posedge clk)begin
  if(!reset_n)begin
   front<=0;front_valid<=0;back<=1;frame_pending<=0;collecting<=0;line_full<=0;line_last<=0;
   pixel_count<=0;input_x<=0;pack_count<=0;packed_line<=0;write_index<=0;read_index<=0;
   pending_reads<=0;scan_state<=DRAIN;reset_count<=0;frame_seen<=0;
   busy<=0;writing<=0;prefer_write<=0;address<=0;write_line<=0;
   completed_frames<=0;displayed_frames<=0;format_errors<=0;
  end else begin
   if(pixel_fire)begin
    if(video_sof)begin
     // A new SOF replaces an incomplete back buffer, never the front buffer.
     packed_line<={224'b0,8'b0,video_data};pack_count<=1;pixel_count<=1;input_x<=1;write_index<=0;
     collecting<=!video_eol;
     if(collecting || video_eol)format_errors<=format_errors+1'b1;
    end else if(collecting)begin
     if(video_eol!=(input_x==16'(WIDTH-1)))begin collecting<=0;pack_count<=0;format_errors<=format_errors+1'b1;end
     else begin
      packed_line[pack_count*32+:32]<={8'b0,video_data};pack_count<=pack_count+1'b1;
      input_x<=input_x==16'(WIDTH-1)?16'd0:input_x+1'b1;pixel_count<=pixel_count+1'b1;
      if(pack_count==7)begin line_full<=1;line_last<=pixel_count==20'(PIXELS-1);end
      if(pixel_count==20'(PIXELS-1))collecting<=0;
     end
    end
   end
   if(!busy && (write_candidate || read_candidate))begin
    writing<=select_write;
    if(select_write)begin
     address<=(back?BASE1:BASE0)+{9'b0,write_index,3'b000};write_line<=packed_line;
    end else address<=(front?BASE1:BASE0)+{9'b0,read_index,3'b000};
    busy<=1;
   end
   if(busy && native_ready)begin busy<=0;prefer_write<=!writing;end
   if(launch_write)begin
    line_full<=0;
    if(line_last)begin frame_pending<=1;completed_frames<=completed_frames+1'b1;write_index<=0;end
    else write_index<=write_index+1'b1;
   end
   if(launch_read)read_index<=read_index+1'b1;
   case({launch_read,native_rvalid})
    2'b10:pending_reads<=pending_reads+1'b1;
    2'b01:pending_reads<=pending_reads-1'b1;
    default:begin end
   endcase
   case(scan_state)
    DRAIN:if(pending_reads==0 && !busy)begin
     if(frame_pending)begin front<=back;back<=front;front_valid<=1;frame_pending<=0;displayed_frames<=displayed_frames+1'b1;end
     read_index<=0;reset_count<=31;scan_state<=RESET_FIFO;
    end
    RESET_FIFO:if(reset_count==0)scan_state<=WAIT_FIFO;else reset_count<=reset_count-1'b1;
    WAIT_FIFO:if(fifo_online)scan_state<=RUN;
    RUN:begin end
   endcase
   if(frame_sync!=frame_seen)begin frame_seen<=frame_sync;scan_state<=DRAIN;end
  end
 end
 // synthesis translate_off
 initial begin assert(WIDTH%8==0 && LINES<131072);assert(FIFO_DEPTH>=16);end
 always @(posedge clk)if(reset_n)begin
  if(native_rvalid)assert(pending_reads!=0)else $fatal(1,"Video received unowned DDR line");
  if(native_rvalid && scan_state==RUN)assert(fifo_ready)else $fatal(1,"Video DDR credit overflow");
  if(launch_write)assert(back!=front || !front_valid)else $fatal(1,"Video overwrote front buffer");
 end
 // synthesis translate_on
endmodule
