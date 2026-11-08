`timescale 1ns/1ps
module cpu_axi_independent_checker #(parameter bit BURST=1)(output bit done=0);
 import or_bo_axi_pkg::*;
 bit clk=0,reset_n=0;
 always #5 clk=~clk;
 logic if_valid=0,if_response_ready=0,data_valid=0,data_response_ready=0,data_store=0;
 logic [31:0] if_address=0,data_address=0,data_write=0;
 logic [3:0] data_mask=15;
 wire if_ready,if_response_valid,data_ready,data_response_valid,data_fault;
 wire [95:0] if_data;wire [2:0] if_fault;wire [31:0] data_read;wire [4:0] data_cause;
 ax_req_t req;ax_rsp_t rsp;
 or_bo_cpu_axi #(.FETCH_BURST(BURST)) dut(.*);
 axi_ram_model #(.WORDS(64)) ram(.*);
 int cycles=0,checks=0;
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(cycles>4000)$fatal(1,"INDEPENDENT_RESPONSE_DEADLOCK burst=%0d state=%0d if=%b/%b data=%b/%b",BURST,dut.state,if_response_valid,if_response_ready,data_response_valid,data_response_ready);
 end
 task automatic fetch(input logic [31:0] address);
  @(negedge clk);if_valid=1;if_address=address;
  do @(posedge clk);while(!if_ready);
  @(negedge clk);if_valid=0;
  while(!if_response_valid)@(negedge clk);
 endtask
 task automatic data_request(input bit store,input logic [31:0] address,input logic [31:0] value);
  @(negedge clk);data_valid=1;data_store=store;data_address=address;data_write=value;
  do @(posedge clk);while(!data_ready);
  @(negedge clk);data_valid=0;
  while(!data_response_valid)@(negedge clk);
 endtask
 task automatic consume_data;
  data_response_ready=1;@(negedge clk);data_response_ready=0;
 endtask
 task automatic consume_fetch;
  if_response_ready=1;@(negedge clk);if_response_ready=0;
 endtask
 initial begin
  repeat(6)@(negedge clk);
  for(int i=0;i<64;i++)ram.mem[i]=32'h12340000+32'(i);
  reset_n=1;
  // Exact cold-boot cycle: unconsumed fetch must not prevent the load that
  // permits decode/retirement to make space for that same fetch response.
  fetch(32'h80000000);
  data_request(0,32'h80000040,0);
  assert(data_read==32'h12340010 && !data_fault)else $fatal(1,"load during stalled fetch");
  assert(if_response_valid && if_fault==0 && if_data==96'h12340002_12340001_12340000)else $fatal(1,"stalled fetch corrupted by load");
  consume_data();checks++;
  data_request(1,32'h80000040,32'hfeed0123);
  assert(!data_fault)else $fatal(1,"store during stalled fetch");consume_data();checks++;
  data_request(0,32'h80000040,0);
  assert(data_read==32'hfeed0123 && !data_fault)else $fatal(1,"store readback");consume_data();
  assert(if_response_valid && if_data==96'h12340002_12340001_12340000)else $fatal(1,"fetch response changed");
  consume_fetch();checks++;
  // Converse case, including preserved store-error cause while fetch proceeds.
  data_request(1,32'h80001000,0);
  assert(data_fault && data_cause==7)else $fatal(1,"store error cause");
  fetch(32'h80000004);
  assert(if_fault==0 && if_data==96'h12340003_12340002_12340001)else $fatal(1,"fetch during stalled data");
  assert(data_response_valid && data_fault && data_cause==7)else $fatal(1,"held data error overwritten by fetch");
  consume_fetch();consume_data();checks++;
  // Reset revokes both independently buffered responses.
  fetch(32'h80000000);data_request(0,32'h80000040,0);
  reset_n=0;repeat(6)@(negedge clk);
  assert(!if_response_valid && !data_response_valid)else $fatal(1,"reset left response valid");
  reset_n=1;fetch(32'h80000008);
  assert(if_data==96'h12340004_12340003_12340002)else $fatal(1,"post-reset fetch");
  consume_fetch();checks++;
  $display("PASS CPU_AXI_INDEPENDENT burst=%0d checks=%0d cycles=%0d",BURST,checks,cycles);done=1;
 end
endmodule
module tb_cpu_axi_independent;
 wire [1:0] done;
 cpu_axi_independent_checker #(.BURST(0)) single(done[0]);
 cpu_axi_independent_checker #(.BURST(1)) burst(done[1]);
 initial begin wait(&done);$display("PASS ALL_CPU_AXI_INDEPENDENT");$finish;end
endmodule
