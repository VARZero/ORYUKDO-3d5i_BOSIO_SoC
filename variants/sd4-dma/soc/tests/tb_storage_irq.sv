`timescale 1ns/1ps
module tb_storage_irq;
 import rv32_pkg::*;
 logic clk=0,reset_n=0;always #5 clk=~clk;
 logic timer_irq=0,external_m_irq=0,external_s_irq=0,issue=0,retire=0;
 logic [7:0] uop=U_CSR;logic [31:0] instruction=0,operand=0;
 wire interrupt_request;wire [4:0] interrupt_cause;wire [1:0] privilege;
 rv32_machine_csrs dut(.clk,.reset_n,.flush(1'b0),.reset_mtvec(32'h80000000),.timer_irq,.external_m_irq,.external_s_irq,
  .time_value(64'b0),.issue,.issue_token(37'd1),.uop,.instruction,.operand,.pc(32'h80000000),
  .read_value(),.next_pc(),.illegal(),.retire_count(3'd1),.retire,.retire_token(37'd1),
  .trap(1'b0),.trap_interrupt(1'b0),.trap_pc(32'b0),.trap_value(32'b0),.trap_cause(5'b0),
  .interrupt_request,.interrupt_cause,.trap_vector(),.privilege,.data_privilege(),.satp(),.sum(),.mxr());
 task automatic write_csr(input logic [11:0] a,input logic [31:0] value);
  @(negedge clk);uop=U_CSR;instruction={a,5'd1,3'b001,5'd0,7'h73};operand=value;issue=1;
  @(negedge clk);issue=0;retire=1;@(negedge clk);retire=0;
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;repeat(3)@(negedge clk);
  write_csr('h304,'haa2);write_csr('h300,'h1808);
  external_m_irq=1;external_s_irq=1;timer_irq=1;@(negedge clk);
  assert(interrupt_request && interrupt_cause==11)else $fatal(1,"MEIP priority");
  external_m_irq=0;@(negedge clk);assert(interrupt_request && interrupt_cause==7);
  timer_irq=0;@(negedge clk);assert(interrupt_request && interrupt_cause==9);
  write_csr('h303,'h222);assert(!interrupt_request)else $fatal(1,"delegated S interrupt in M");
  write_csr('h344,'h22);write_csr('h300,'h882);
  @(negedge clk);uop=U_MRET;issue=1;@(negedge clk);issue=0;retire=1;@(negedge clk);retire=0;
  assert(privilege==1 && interrupt_request && interrupt_cause==9)else $fatal(1,"S external interrupt");
  external_s_irq=0;@(negedge clk);assert(interrupt_request && interrupt_cause==1)else $fatal(1,"SSIP priority");
  timer_irq=1;@(negedge clk);assert(interrupt_request && interrupt_cause==7)else $fatal(1,"M preempts S");
  $display("PASS CSR external IRQ mask, M/S delegation, privilege and priority");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
