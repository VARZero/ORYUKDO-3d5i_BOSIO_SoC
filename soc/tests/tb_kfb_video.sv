`timescale 1ns/1ps
module tb_kfb_video;
 reg clk=0,pixel_clk=0;always #5 clk=~clk;
`ifdef KFB_VIDEO_720P
 localparam W=1280,H=720,HF=110,HS=40,HB=220,VF=5,VS=5,VB=20,DEPTH=512;
 localparam FRAMES=6,CYCLE_LIMIT=25000000,PAUSE_CYCLES=200000,GOOD_TARGET=3,RECOVERY_TARGET=1;
 always #6.734 pixel_clk=~pixel_clk;
`else
 localparam W=16,H=8,HF=16,HS=4,HB=16,VF=6,VS=2,VB=12,DEPTH=16;
 localparam FRAMES=8,CYCLE_LIMIT=150000,PAUSE_CYCLES=5000,GOOD_TARGET=5,RECOVERY_TARGET=2;
 always #7 pixel_clk=~pixel_clk;
`endif
 function automatic [23:0] colour(input int x,y,f);
`ifdef KFB_VIDEO_720P
  return {3'(f),10'(y),11'(x)};
`else
  return {8'(x),8'(y),8'(f)};
`endif
 endfunction
 reg reset_n=0,pause=0;reg [23:0] video_data=0;reg video_valid=0,video_sof=0,video_eol=0;wire video_ready;
 wire [23:0] rgb;wire hsync,vsync,de,underflow_sticky;
 wire pixel_reset_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) pixel_release(
  .src_arst(reset_n),.dest_clk(pixel_clk),.dest_arst(pixel_reset_n));
 wire [31:0] completed_frames,displayed_frames,format_errors;
 wire [1:0] nv,nw,nready,nrv;wire [28:0] na[2];wire [255:0] nd[2];wire [31:0] nm[2];wire [255:0] nrd;
 assign nv[0]=0;assign nw[0]=0;assign na[0]=0;assign nd[0]=0;assign nm[0]=0;
 kfb_video #(.WIDTH(W),.HEIGHT(H),.H_FRONT(HF),.H_SYNC(HS),.H_BACK(HB),.V_FRONT(VF),.V_SYNC(VS),.V_BACK(VB),.FIFO_DEPTH(DEPTH)) dut(
  .clk,.pixel_clk,.reset_n,.pixel_reset_n,.video_data,.video_valid,.video_sof,.video_eol,.video_ready,
  .native_valid(nv[1]),.native_write(nw[1]),.native_addr(na[1]),.native_data(nd[1]),.native_mask(nm[1]),
  .native_ready(nready[1]),.native_rvalid(nrv[1]),.native_rdata(nrd),
  .rgb,.hsync,.vsync,.de,.completed_frames,.displayed_frames,.format_errors,.underflow_sticky);
 wire app_en,app_rdy,app_wdf_wren,app_wdf_end,app_wdf_rdy,app_rd_data_valid,app_rd_data_end;
 wire [2:0] app_cmd;wire [28:0] app_addr;wire [255:0] app_wdf_data,app_rd_data;wire [31:0] app_wdf_mask;
 kfb_native_arbiter arb(.clk,.reset_n,.req_valid(nv),.req_write(nw),.req_addr(na),.req_data(nd),.req_mask(nm),
  .req_ready(nready),.rsp_valid(nrv),.rsp_data(nrd),.*);
 kfb_native_ram_model ram(.*);
 int cycles=0,pixels=0,good_frames=0,recovered=0,frame_id=0,frame_pixels=0;
 bit stalled_once=0;logic previous_front=0;
 always @(posedge clk)begin
  cycles++;if(cycles>CYCLE_LIMIT)$fatal(1,"Video timeout frames=%0d displayed=%0d good=%0d recovery=%0d",completed_frames,displayed_frames,good_frames,recovered);
  if(reset_n && dut.front!=previous_front)assert(!de)else $fatal(1,"Front buffer changed during active pixels");
  previous_front<=dut.front;
 end
 // Check coordinates and constant frame identity, allowing black output during
 // deliberate memory starvation. A shifted FIFO word or torn frame fails.
 always @(negedge pixel_clk)if(dut.pixel_reset_n)begin
  if(dut.px==0 && dut.py==0)begin frame_id=0;frame_pixels=0;end
  if(de && rgb!=0)begin
`ifdef KFB_VIDEO_720P
   if(frame_id==0)frame_id=int'(rgb[23:21]);
`else
   if(frame_id==0)frame_id=int'(rgb[7:0]);
`endif
   assert(rgb==colour(int'(dut.px),int'(dut.py),frame_id))
    else $fatal(1,"Shifted or torn video pixel %h at %0d,%0d frame=%0d",rgb,dut.px,dut.py,frame_id);
   pixels++;frame_pixels++;
  end
  if(dut.px==W && dut.py==H-1 && frame_pixels==W*H)begin good_frames++;if(stalled_once && !pause)recovered++;end
 end
 task automatic send(input logic [23:0] d,input bit sof,eol);
  @(negedge clk);video_valid=1;video_data=d;video_sof=sof;video_eol=eol;
  do @(posedge clk);while(!video_ready);
  @(negedge clk);video_valid=0;
 endtask
 initial begin
  repeat(40)@(negedge clk);reset_n=1;
  fork
   begin
    send(24'h000001,1,0);send(24'h010001,0,1); // Bad early EOL must never publish.
    for(int f=1;f<=FRAMES;f++)begin
     for(int y=0;y<H;y++)for(int x=0;x<W;x++)send(colour(x,y,f),x==0 && y==0,x==W-1);
    end
   end
   begin
    wait(good_frames>=2);@(negedge clk);pause=1;stalled_once=1;
    repeat(PAUSE_CYCLES)@(negedge clk);pause=0;
   end
  join
  wait(completed_frames==FRAMES && good_frames>=GOOD_TARGET && recovered>=RECOVERY_TARGET);
  repeat(20)@(negedge clk);
  assert(format_errors==1 && underflow_sticky)else $fatal(1,"Missing format/underflow recovery coverage");
`ifdef KFB_VIDEO_720P
  $display("PASS KFB_VIDEO_720P width=%0d height=%0d fifo=%0d frames=%0d displayed=%0d good=%0d recovered=%0d pixels=%0d format_errors=%0d underflow=%b cycles=%0d",W,H,DEPTH,completed_frames,displayed_frames,good_frames,recovered,pixels,format_errors,underflow_sticky,cycles);
`else
  $display("PASS KFB_VIDEO frames=%0d displayed=%0d good=%0d recovered=%0d pixels=%0d format_errors=%0d underflow=%b cycles=%0d",completed_frames,displayed_frames,good_frames,recovered,pixels,format_errors,underflow_sticky,cycles);
`endif
  $finish;
 end
endmodule
