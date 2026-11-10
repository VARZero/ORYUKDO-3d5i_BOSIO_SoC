`timescale 1ns/1ps
// Behavioral DDR storage, not a DDR PHY model. Independent MIG command/WDF
// stalls, queued execution and delayed ordered read responses are exercised.
module kfb_native_ram_model(
 input wire clk,reset_n,pause,app_en,input wire [2:0] app_cmd,input wire [28:0] app_addr,
 output wire app_rdy,input wire app_wdf_wren,app_wdf_end,
 input wire [255:0] app_wdf_data,input wire [31:0] app_wdf_mask,
 output wire app_wdf_rdy,output logic app_rd_data_valid,app_rd_data_end,
 output logic [255:0] app_rd_data
);
 // Keep the dense firmware region as an ordinary array, with sparse storage
 // above it. This covers the full 1 GiB without allocating untouched high RAM.
 bit [31:0] mem[131072];bit [31:0] high_mem[bit [27:0]];
 string image_name;
 integer cycles=0,commands=0,write_commands=0,read_commands=0,seed=1;
 logic [28:0] ca[64];logic cw[64];integer cp=0,cr=0,cc=0;
 logic [255:0] wd[64];logic [31:0] wm[64];integer dp=0,dr=0,dc=0;
 logic [255:0] response[64];integer due[64];integer rp=0,rr=0,rc=0;
 logic [255:0] line_value;bit [27:0] wi;bit [31:0] word_value;
 function automatic bit [31:0] read_word(input bit [27:0] a);
  if(a<131072)return mem[a];
  return (high_mem.exists(a)!=0)?high_mem[a]:0;
 endfunction
 initial begin
  if($value$plusargs("seed=%d",seed))begin end
  if($value$plusargs("image=%s",image_name))begin
   $readmemh(image_name,mem);
  end
 end
 logic cmd_ready_q=0,data_ready_q=0;
 // Drive stalls on the opposite edge to avoid a testbench sampling race.
 always @(negedge clk)begin
  cmd_ready_q<=reset_n && !pause && cc<60 && (cycles+seed)%5!=0;
  data_ready_q<=reset_n && !pause && dc<60 && (cycles+seed)%7!=0 && (cycles+seed)%7!=1;
 end
 assign app_rdy=reset_n && cmd_ready_q;
 assign app_wdf_rdy=reset_n && data_ready_q;
 always @(posedge clk)begin
  if(!reset_n)begin cycles=0;commands=0;write_commands=0;read_commands=0;
   cp=0;cr=0;cc=0;dp=0;dr=0;dc=0;rp=0;rr=0;rc=0;
   app_rd_data_valid<=0;app_rd_data_end<=0;app_rd_data<=0;end
  else begin
   app_rd_data_valid<=0;app_rd_data_end<=0;
   if(rc!=0 && due[rr]<=cycles)begin
    app_rd_data<=response[rr];app_rd_data_valid<=1;app_rd_data_end<=1;rr=(rr+1)%64;rc--;
   end
   if(cc!=0)begin
    if(cw[cr] && dc!=0)begin
     for(int n=0;n<8;n++)begin
      wi=28'(ca[cr])+28'(n);
      word_value=read_word(wi);
      for(int b=0;b<4;b++)if(!wm[dr][n*4+b])word_value[b*8+:8]=wd[dr][n*32+b*8+:8];
      if(wi<131072)mem[wi]=word_value;else high_mem[wi]=word_value;
     end
     cr=(cr+1)%64;cc--;dr=(dr+1)%64;dc--;
    end else if(!cw[cr] && rc<60)begin
     for(int n=0;n<8;n++)begin wi=28'(ca[cr])+28'(n);line_value[n*32+:32]=read_word(wi);end
     response[rp]=line_value;due[rp]=cycles+12+(cycles%5);rp=(rp+1)%64;rc++;
     cr=(cr+1)%64;cc--;
    end
   end
   if(app_en && app_rdy)begin
    assert(app_cmd==0 || app_cmd==1)else $fatal(1,"Unexpected native command");
    assert(app_addr[2:0]==0 && app_addr[28]==0)else $fatal(1,"Native address outside aligned 1 GiB");
    ca[cp]=app_addr;cw[cp]=app_cmd==0;cp=(cp+1)%64;cc++;commands++;
    if(app_cmd==0)write_commands++;else read_commands++;
   end
   if(app_wdf_wren && app_wdf_rdy)begin
    assert(app_wdf_end)else $fatal(1,"Native BL8 end missing");
    wd[dp]=app_wdf_data;wm[dp]=app_wdf_mask;dp=(dp+1)%64;dc++;
   end
   cycles++;
  end
 end
endmodule
