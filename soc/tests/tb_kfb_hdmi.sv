`timescale 1ns/1ps
module tb_kfb_hdmi;
 reg pixel_clk=0,serial_clk=0,reset_n=0;
 reg clocks_enable=1;
 always #5 if(clocks_enable)pixel_clk=~pixel_clk;
 always #1 if(clocks_enable)serial_clk=~serial_clk;
 reg [23:0] rgb=0;reg de=0,hs=0,vs=0;
 wire [9:0] encoded;wire cp,cn;wire [2:0] dp,dn;
 wire pixel_reset_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) pixel_release(
  .src_arst(reset_n),.dest_clk(pixel_clk),.dest_arst(pixel_reset_n));
 TMDS_Encoder enc(.pDataOut(rgb[7:0]),.pC0(hs),.pC1(vs),.pVde(de),
  .PixelClk(pixel_clk),.SerialClk(serial_clk),.aRst(!reset_n),.pDataOutRaw(encoded));
 kfb_hdmi tx(.pixel_clk,.serial_clk,.reset_n(pixel_reset_n),.rgb,.de,.hsync(hs),.vsync(vs),
  .clock_p(cp),.clock_n(cn),.data_p(dp),.data_n(dn));
 function automatic [9:0] reference_encode(input bit [7:0] d,input bit active,c0,c1,inout int bias);
  bit [8:0] q;bit inv;int ones;
  if(!active)begin
   bias=0;
   case({c1,c0})
    0:return 10'b1101010100;1:return 10'b0010101011;
    2:return 10'b0101010100;3:return 10'b1010101011;
   endcase
  end
  ones=$countones(d);q[8]=!(ones>4 || (ones==4 && !d[0]));q[0]=d[0];
  for(int n=1;n<8;n++)q[n]=q[n-1]^d[n]^!q[8];
  ones=$countones(q[7:0]);
  if(bias==0 || ones==4)begin
   inv=!q[8];bias+=q[8]?(2*ones-8):(8-2*ones);
  end else if((bias>0 && ones>4)||(bias<0 && ones<4))begin
   inv=1;bias+=2*int'(q[8])+8-2*ones;
  end else begin inv=0;bias+=2*ones-8-2*int'(!q[8]);end
  return {inv,q[8],q[7:0]^{8{inv}}};
 endfunction
 function automatic [7:0] decode(input bit [9:0] t);
  bit [7:0] q,d;q=t[7:0]^{8{t[9]}};d[0]=q[0];
  for(int n=1;n<8;n++)d[n]=q[n]^q[n-1]^!t[8];
  return d;
 endfunction
 function automatic bit control(input bit [9:0] t);
  return t inside {10'b1101010100,10'b0010101011,10'b0101010100,10'b1010101011};
 endfunction
 int bias=0,cycles=0,encoder_checks=0,received=0;
 reg [9:0] expected[3];
 always @(posedge pixel_clk)begin
  expected[0]=expected[1];expected[1]=expected[2];
  expected[2]=reference_encode(rgb[7:0],de,hs,vs,bias);
  cycles++;
  #0.1;
  if(cycles>5)begin
   assert(encoded===expected[0])else $fatal(1,"TMDS disparity/pipeline mismatch cycle=%0d got=%b expected=%b",cycles,encoded,expected[0]);
   encoder_checks++;
  end
 end
 int lane=0;bit previous_clock=0,aligned=0;
 reg [9:0] words[3];reg [23:0] decoded;
 always @(serial_clk)begin
  #0.2;
  if(reset_n && cycles>25)begin
   assert(cn===!cp && dn===~dp)else $fatal(1,"Differential HDMI output mismatch");
   if(previous_clock && !cp)begin lane=0;aligned=1;end
   if(aligned)begin
    for(int n=0;n<3;n++)words[n][lane]=dp[n];
    if(lane==9)begin
     if(!control(words[0]))begin
      decoded={decode(words[2]),decode(words[1]),decode(words[0])};
      assert(decoded=={8'(received),8'(received*3),8'(received^'h55)})
       else $fatal(1,"Serialized RGB/order mismatch pixel=%0d got=%h",received,decoded);
      received++;
     end
     aligned=0;
    end else lane++;
   end
   previous_clock=cp;
  end
 end
 initial begin
  repeat(30)@(negedge pixel_clk);reset_n=1;
  repeat(20)@(negedge pixel_clk);
  for(int n=0;n<256;n++)begin
   de=1;rgb={8'(n),8'(n*3),8'(n^'h55)};@(negedge pixel_clk);
  end
  de=0;
  for(int n=0;n<4;n++)begin {vs,hs}=2'(n);repeat(10)@(negedge pixel_clk);end
  repeat(20)@(negedge pixel_clk);
  assert(received==256)else $fatal(1,"Missing serialized pixels: %0d",received);
  // A clock-stop/reset event must recover through the external reset adapter
  // without editing the official encoder or serializer internals.
  reset_n=0;aligned=0;previous_clock=0;
  repeat(4)@(negedge pixel_clk);
  clocks_enable=0;#1000;clocks_enable=1;
  repeat(8)@(negedge pixel_clk);
  received=0;reset_n=1;
  repeat(20)@(negedge pixel_clk);
  for(int n=0;n<256;n++)begin
   de=1;rgb={8'(n),8'(n*3),8'(n^'h55)};@(negedge pixel_clk);
  end
  de=0;repeat(20)@(negedge pixel_clk);
  assert(received==256)else $fatal(1,"Missing pixels after reset/clock restart: %0d",received);
  $display("PASS KFB_HDMI encoder_checks=%0d serialized_pixels=512 clock_stop_reset_recovery=1",encoder_checks);$finish;
 end
endmodule
