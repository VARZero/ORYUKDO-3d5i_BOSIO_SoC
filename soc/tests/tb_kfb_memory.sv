`timescale 1ns/1ps
module tb_kfb_memory;
 import or_bo_axi_pkg::*;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0;ax_req_t req='0;ax_rsp_t rsp;
 wire pause=1'b0;
 wire [1:0] nv,nw,nready,nrv;wire [28:0] na[2];wire [255:0] nd[2];wire [31:0] nm[2];wire [255:0] nrd;
 reg v1=0,w1=0;reg [28:0] a1=0;reg [255:0] d1=0;reg [31:0] m1=0;
 assign nv[1]=v1;assign nw[1]=w1;assign na[1]=a1;assign nd[1]=d1;assign nm[1]=m1;
 kfb_axi_mig bridge(.clk,.reset_n,.req,.rsp,.native_valid(nv[0]),.native_write(nw[0]),.native_addr(na[0]),
  .native_data(nd[0]),.native_mask(nm[0]),.native_ready(nready[0]),.native_rvalid(nrv[0]),.native_rdata(nrd));
 wire app_en,app_rdy,app_wdf_wren,app_wdf_end,app_wdf_rdy,app_rd_data_valid,app_rd_data_end;
 wire [2:0] app_cmd;wire [28:0] app_addr;wire [255:0] app_wdf_data,app_rd_data;wire [31:0] app_wdf_mask;
 kfb_native_arbiter arb(.clk,.reset_n,.req_valid(nv),.req_write(nw),.req_addr(na),.req_data(nd),.req_mask(nm),
  .req_ready(nready),.rsp_valid(nrv),.rsp_data(nrd),.*);
 kfb_native_ram_model ram(.*);
 int checks=0,cycles=0,second_reads=0,max_pending=0;
 always @(posedge clk)begin
  cycles++;if(cycles>300000)$fatal(1,"Memory integration timeout");
  if(reset_n && int'(arb.count)>max_pending)max_pending=int'(arb.count);
  if(reset_n && nrv[1])begin
   assert(nrd=={8{32'h13570000+32'(second_reads)}})else $fatal(1,"Native response owner/order corruption %0d",second_reads);
   second_reads++;
  end
 end
 function automatic [31:0] pattern(input int i,input int n);return 32'hb00c0000 ^ (32'(i)<<12) ^ 32'(n);endfunction
 task automatic aw(input logic [63:0] a,input int len,input logic [1:0] burst=1);
  @(negedge clk);req.aw='0;req.aw.addr=a;req.aw.len=8'(len-1);req.aw.size=2;req.aw.burst=burst;req.aw.id=1;req.awvalid=1;
  do @(posedge clk);while(!rsp.awready);
  @(negedge clk);req.awvalid=0;
 endtask
 task automatic w(input logic [31:0] data,input logic [3:0] mask,input bit last);
  req.w.data=data;req.w.strb=mask;req.w.last=last;req.wvalid=1;
  do @(posedge clk);while(!rsp.wready);
  @(negedge clk);req.wvalid=0;
 endtask
 task automatic b(input logic [1:0] response);
  req.bready=0;while(!rsp.bvalid)@(negedge clk);
  repeat(3)begin @(negedge clk);assert(rsp.bvalid && rsp.b.id==1 && rsp.b.resp==response)else $fatal(1,"B response");end
  req.bready=1;@(negedge clk);req.bready=0;checks++;
 endtask
 task automatic ar(input logic [63:0] a,input int len,input logic [1:0] burst=1);
  @(negedge clk);req.ar='0;req.ar.addr=a;req.ar.len=8'(len-1);req.ar.size=2;req.ar.burst=burst;req.ar.id=1;req.arvalid=1;
  do @(posedge clk);while(!rsp.arready);
  @(negedge clk);req.arvalid=0;
 endtask
 task automatic r(input logic [31:0] expected,input logic [1:0] response,input bit last);
  req.rready=0;while(!rsp.rvalid)@(negedge clk);
  repeat(2)begin @(negedge clk);
   assert(rsp.rvalid && rsp.r.resp==response && rsp.r.last==last && rsp.r.id==1)else $fatal(1,"R protocol");
   if(response==OKAY)assert(rsp.r.data==expected)else $fatal(1,"R data expected=%h got=%h",expected,rsp.r.data);
  end
  req.rready=1;@(negedge clk);req.rready=0;checks++;
 endtask
 initial begin
  repeat(25)@(negedge clk);reset_n=1;
  fork
   begin
    for(int i=0;i<16;i++)begin
     @(negedge clk);v1=1;w1=1;a1=29'h0d000000+29'(i*8);d1={8{32'h13570000+32'(i)}};
     do @(posedge clk);while(!nready[1]);
     @(negedge clk);v1=0;
    end
    for(int i=0;i<16;i++)begin
     v1=1;w1=0;a1=29'h0d000000+29'(i*8);
     do @(posedge clk);while(!nready[1]);
     @(negedge clk);v1=0;
    end
   end
   begin
    // Same low offset in all eight 128 MiB regions must not alias.
    for(int i=0;i<8;i++)begin aw(64'h80000100+64'(i)*64'h08000000,1);w(pattern(i,0),15,1);b(OKAY);end
    for(int i=0;i<8;i++)begin ar(64'h80000100+64'(i)*64'h08000000,1);r(pattern(i,0),OKAY,1);end
    aw(64'hbffffffc,1);w(32'h12345678,15,1);b(OKAY);
    aw(64'hbffffffc,1);w(32'hff000000,8,1);b(OKAY);
    ar(64'hbffffffc,1);r(32'hff345678,OKAY,1);
    for(int i=0;i<24;i++)begin
     automatic int len=(i%4==0)?256:((i%4==1)?16:((i%4==2)?8:3));
     aw(64'h80002000+64'(i)*4096,len);
     for(int n=0;n<len;n++)w(pattern(i,n),15,n==len-1);b(OKAY);
     ar(64'h80002000+64'(i)*4096,len);
     for(int n=0;n<len;n++)r(pattern(i,n),OKAY,n==len-1);
    end
    aw(64'h80001000,4,0);for(int n=0;n<4;n++)w(32'(n+100),15,n==3);b(OKAY);
    ar(64'h80001000,4,0);repeat(3)r(103,OKAY,0);r(103,OKAY,1);
    aw(64'h80001400,2);w(9,15,1);w(10,15,1);b(SLVERR);
    begin
     automatic int old_commands=ram.commands;
     ar(64'hc0000000,1);r(0,DECERR,1);
     ar(64'h180000000,1);r(0,DECERR,1);
     ar(64'h80000ffc,2);r(0,DECERR,0);r(0,DECERR,1);
     aw(64'hc0000000,2);w(1,15,0);w(2,15,1);b(DECERR);
     assert(ram.commands==old_commands)else $fatal(1,"Invalid address reached DDR");
    end
   end
  join
  while(second_reads!=16)@(negedge clk);
  assert(max_pending>1)else $fatal(1,"Pipelined read tag coverage absent");
  $display("PASS KFB_MEMORY checks=%0d second_client_reads=%0d max_pending=%0d commands=%0d cycles=%0d",checks,second_reads,max_pending,ram.commands,cycles);$finish;
 end
endmodule
