`timescale 1ns/1ps
module tb_storage_dma;
 import or_bo_axi_pkg::*;
 logic clk=0,reset_n=0;always #5 clk=~clk;
 al_req_t req;al_rsp_t rsp;
 ax_req_t masters[5],memory;ax_rsp_t replies[5],memory_reply;
 al_req_t lite[LITE_PORTS];al_rsp_t lite_reply[LITE_PORTS];
 logic lock_request=0;wire lock_grant,snoop_valid,busy;wire [31:0] snoop_address;wire [2:0] active_master;
 wire irq,sd_ready,sd_done,sd_error;logic sd_start=0,sd_to_memory=0;
 logic [31:0] sd_address=0;logic [9:0] sd_bytes=0;
 wire [8:0] buffer_address;wire [7:0] buffer_wdata,buffer_rdata;wire buffer_we;
 logic [7:0] buffer_mem[512];assign buffer_rdata=buffer_mem[buffer_address];
 int current_trial=-1;int cycles=0,snoops=0;wire snoop_ready=cycles%7!=0;
 always @(posedge clk) begin
   cycles<=cycles+1;if(cycles>1000000)$fatal(1,"timeout trial=%0d dma_state=%0d left=%0d count=%0d index=%0d op=%0d src=%h dst=%h fabric_state=%0d owner=%0d queued=%b irq=%b",current_trial,dma.state,dma.left,dma.count,dma.index,dma.operation,dma.src,dma.dst,fabric.state,active_master,dma.queued,irq);
   if(buffer_we) buffer_mem[buffer_address]<=buffer_wdata;
   if(snoop_valid && snoop_ready) snoops<=snoops+1;
 end
 or_storage_dma dma(.clk,.reset_n,.req,.rsp,.memory(masters[4]),.reply(replies[4]),.irq,
  .sd_start,.sd_to_memory,.sd_address,.sd_bytes,.sd_ready,.sd_done,.sd_error,
  .buffer_address,.buffer_wdata,.buffer_we,.buffer_rdata);
 or_bo_axi_fabric #(.MASTERS(5)) fabric(.*);
 axi_ram_model #(.WORDS(16384)) ram(.clk,.reset_n,.req(memory),.rsp(memory_reply));
 task automatic put(input int addr,input logic [31:0] value);
  bit ah,wh;ah=0;wh=0;
  @(negedge clk);req='0;req.awaddr=32'(addr);req.wdata=value;req.wstrb=15;req.awvalid=1;req.wvalid=1;
  while(!ah || !wh) begin
   @(posedge clk);if(req.awvalid && rsp.awready) ah=1;if(req.wvalid && rsp.wready) wh=1;
   @(negedge clk);req.awvalid=!ah;req.wvalid=!wh;
  end
  req.bready=1;do @(posedge clk);while(!rsp.bvalid);
  assert(rsp.bresp==OKAY) else $fatal(1,"register write %0d",addr);
  @(negedge clk);req='0;
 endtask
 task automatic wait_job(input bit fail_expected=0);
  wait(irq);@(negedge clk);
  assert(dma.job_error==fail_expected) else $fatal(1,"DMA error mismatch");
  put(20,2);
 endtask
 task automatic traffic(input int m);
  for(int i=0;i<80;i++) begin
   @(negedge clk);masters[m]='0;masters[m].ar.addr=64'h80000000+64'(m*128);masters[m].ar.size=2;masters[m].ar.burst=1;masters[m].arvalid=1;
   do @(posedge clk);while(!replies[m].arready);
   @(negedge clk);masters[m].arvalid=0;masters[m].rready=1;
   do @(posedge clk);while(!replies[m].rvalid);
   assert(replies[m].r.resp==OKAY);@(negedge clk);masters[m]='0;
  end
 endtask
 initial begin
  req='0;for(int i=0;i<4;i++) masters[i]='0;for(int i=0;i<LITE_PORTS;i++)lite_reply[i]='0;
  for(int i=0;i<512;i++)buffer_mem[i]=8'(i*13+3);
  repeat(5)@(negedge clk);reset_n=1;
  for(int i=0;i<4096;i++)ram.mem[i]=32'(i)^32'h6e89a135;
  // Different source/destination 4-KiB offsets, simultaneous all-master reads.
  put(0,'h80000ff4);put(4,'h80004fec);put(8,1028);
  fork
   begin put(16,'h101);wait_job();end
   traffic(0);traffic(1);traffic(2);traffic(3);
  join
  for(int i=0;i<257;i++)assert(ram.mem['h4fec/4+i]==ram.mem['hff4/4+i])else $fatal(1,"copy %0d",i);
  put(4,'h80006004);put(8,260);put(12,'h55aa19e7);put(16,'h102);wait_job();
  for(int i=0;i<65;i++)assert(ram.mem['h6004/4+i]=='h55aa19e7)else $fatal(1,"fill");
  // Atomic lock holds the new master off the RAM bus.
  lock_request=1;wait(lock_grant);put(4,'h80007000);put(8,64);put(16,'h102);
  repeat(100)@(negedge clk);assert(!irq && dma.state!=dma.IDLE)else $fatal(1,"lock bypass");
  lock_request=0;wait_job();
  // Card -> RAM while a generic fill is queued; both completions stay distinct.
  sd_address='h80002000;sd_bytes=512;sd_to_memory=1;sd_start=1;@(negedge clk);sd_start=0;
  put(4,'h80003000);put(8,64);put(12,'h7e7e7e7e);put(16,'h102);
  wait(sd_done);assert(!sd_error);wait_job();
  for(int i=0;i<512;i++)assert(ram.mem['h2000/4+i/4][8*(i%4)+:8]==8'(i*13+3))else $fatal(1,"SD receive %0d",i);
  sd_to_memory=0;sd_start=1;@(negedge clk);sd_start=0;wait(sd_done);assert(!sd_error);
  for(int i=0;i<512;i++)assert(buffer_mem[i]==8'(i*13+3))else $fatal(1,"SD transmit");
  // Invalid descriptor, overlapping memcpy, and RAM response error.
  put(4,'h7ffffffc);put(8,64);put(16,'h102);wait_job(1);
  put(0,'h80002000);put(4,'h80002004);put(8,64);put(16,'h101);wait_job(1);
  put(4,'h80020000);put(8,64);put(16,'h102);wait_job(1);
  put(0,'h80020000);put(4,'h80007000);put(8,64);put(16,'h101);wait_job(1);
  // Deterministic randomized descriptor stress, independent per-byte RAM oracle.
  for(int trial=0;trial<256;trial++) begin
   automatic int words_n=1+$urandom_range(0,127);
   automatic int src_word=$urandom_range(0,3071);
   automatic int dst_word=4096+$urandom_range(0,3071);
   automatic logic [31:0] value=$urandom;
   automatic bit fill=$urandom_range(0,1)!=0;
   current_trial=trial;
   put(0,32'h80000000+32'(src_word*4));put(4,32'h80000000+32'(dst_word*4));
   put(8,32'(words_n*4));put(12,value);put(16,fill?'h102:'h101);wait_job();
   for(int j=0;j<words_n;j++) assert(ram.mem[dst_word+j]==(fill?value:ram.mem[src_word+j]))
    else $fatal(1,"random descriptor trial=%0d word=%0d",trial,j);
  end
  assert(snoops>=257+65+16+128+16)else $fatal(1,"missing reservation invalidations %0d",snoops);
  $display("PASS DMA copy/fill, 4KiB split, 5-master contention, atomic lock, snoops, SD directions, queue, errors, 256 randomized descriptors cycles=%0d",cycles);$finish;
 end
endmodule
