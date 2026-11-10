"""Compare unchanged board-example and official Digilent encoders in XSIM.

Source archives and pinned upstream hashes are retained under hdmi_source_audit.
The existing working copy is a third comparator, not the golden implementation.
"""
from pathlib import Path
import subprocess, json, hashlib

root = Path(__file__).resolve().parents[2]
out = root / 'soc/reports/hdmi_source_audit'
bin_dir = Path('D:/Xilinx2202/Vivado/2022.2/bin')
vendor = root / 'soc/board/vendor/hdmi'
sources = json.loads((out/'upstream_sources.json').read_text())
for item in sources['files']:
    assert hashlib.sha256((out/item['file']).read_bytes()).hexdigest() == item['sha256']
original = json.loads((vendor/'original_sha256.json').read_text())
assert hashlib.sha256((out/'original_TMDSEncoder.vhd').read_bytes()).hexdigest() == original['TMDSEncoder.vhd']

(out/'encoder_comparison.vhd').write_text('''library ieee;
use ieee.std_logic_1164.all;
library original, upstream, patched;
entity encoder_comparison is
 port(clk, rst, de, c0, c1 : in std_logic;
      data_in : in std_logic_vector(7 downto 0);
      old_code, official_code, working_code : out std_logic_vector(9 downto 0));
end entity;
architecture compare of encoder_comparison is begin
 old_ip: entity original.TMDSEncoder
 port map(D_I=>data_in,C0_I=>c0,C1_I=>c1,DE_I=>de,CLK_I=>clk,RST_I=>rst,D_O=>old_code);
 official_ip: entity upstream.TMDS_Encoder
 port map(PixelClk=>clk,SerialClk=>clk,aRst=>rst,pDataOut=>data_in,
          pC0=>c0,pC1=>c1,pVde=>de,pDataOutRaw=>official_code);
 working_ip: entity patched.TMDSEncoder
 port map(D_I=>data_in,C0_I=>c0,C1_I=>c1,DE_I=>de,CLK_I=>clk,RST_I=>rst,D_O=>working_code);
end architecture;
''')
(out/'tb_encoder_comparison.sv').write_text(r'''`timescale 1ns/1ps
module tb_encoder_comparison;
 reg clk=0,rst=1,de=0,c0=0,c1=0;reg [7:0] data_in=0;
 always #5 clk=~clk;
 wire [9:0] old_code,official_code,working_code;
 encoder_comparison dut(.clk(clk),.rst(rst),.de(de),.c0(c0),.c1(c1),.data_in(data_in),
  .old_code(old_code),.official_code(official_code),.working_code(working_code));
 reg [7:0] data_pipe[3];reg [2:0] active_pipe;
 reg [1:0] control_pipe[3];
 int cycles=0,active_checks=0,blank_checks=0,old_differences=0;
 int old_balance=0,official_balance=0,old_max=0,official_max=0;
 function automatic int magnitude(input int n);return n<0?-n:n;endfunction
 function automatic [7:0] decode(input bit [9:0] symbol);
  bit [7:0] q,d;q=symbol[7:0]^{8{symbol[9]}};d[0]=q[0];
  for(int n=1;n<8;n++)d[n]=q[n]^q[n-1]^!symbol[8];
  return d;
 endfunction
 function automatic [9:0] token(input bit [1:0] c);
  case(c)
   0:return 10'b1101010100;1:return 10'b0010101011;
   2:return 10'b0101010100;3:return 10'b1010101011;
  endcase
 endfunction
 always @(posedge clk) begin
  data_pipe[0]=data_pipe[1];data_pipe[1]=data_pipe[2];data_pipe[2]=data_in;
  control_pipe[0]=control_pipe[1];control_pipe[1]=control_pipe[2];control_pipe[2]={c1,c0};
  active_pipe={de,active_pipe[2:1]};cycles++;
  #0.1;
  if(cycles>10)begin
   // Official, unmodified Digilent RTL supplies the encoded word oracle.
   assert(working_code===official_code)else $fatal(1,"Working/official mismatch cycle=%0d",cycles);
   if(active_pipe[0])begin
    assert(decode(old_code)===data_pipe[0] && decode(official_code)===data_pipe[0])
      else $fatal(1,"Decoded byte/latency mismatch cycle=%0d",cycles);
    active_checks++;
    old_balance+=2*$countones(old_code)-10;
    official_balance+=2*$countones(official_code)-10;
    if(magnitude(old_balance)>old_max)old_max=magnitude(old_balance);
    if(magnitude(official_balance)>official_max)official_max=magnitude(official_balance);
    if(old_code!==official_code)begin
     old_differences++;
     if(old_differences<=5)$display("ORIGINAL_DIFFERENCE cycle=%0d input=%h original=%b official=%b original_balance=%0d official_balance=%0d",cycles,data_pipe[0],old_code,official_code,old_balance,official_balance);
    end
   end else begin
    assert(old_code===token(control_pipe[0]) && official_code===token(control_pipe[0]))
      else $fatal(1,"Control/latency mismatch cycle=%0d",cycles);
    old_balance=0;official_balance=0;blank_checks++;
   end
  end
 end
 task automatic drive(input bit active,input bit [7:0] data,input bit [1:0] c=0);
  @(negedge clk);de=active;data_in=data;{c1,c0}=c;
 endtask
 reg [31:0] lfsr=32'h172903a5;
 initial begin
  repeat(30)@(negedge clk);rst=0;
  repeat(10)drive(0,0);
  // Every ordered adjacent byte pair, repeated across an active interval.
  for(int pair=0;pair<65536;pair++)begin
   repeat(4)drive(0,0,2'(pair));
   repeat(4)begin drive(1,8'(pair>>8));drive(1,8'(pair));end
  end
  // Full-width lines reveal cumulative transmitted DC imbalance.
  for(int line=0;line<128;line++)begin
   repeat(32)drive(0,0,2'(line));
   for(int pixel=0;pixel<1280;pixel++)begin
    lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
    drive(1,lfsr[7:0]);
   end
  end
  repeat(20)drive(0,0);
  assert(old_differences>0)else $fatal(1,"Original difference not reproduced");
  $display("PASS HDMI_ENCODER_AUDIT active=%0d blank=%0d original_official_differences=%0d original_max_abs_line_balance=%0d official_max_abs_line_balance=%0d working_matches_official=1 all_decoded_bytes_match=1",active_checks,blank_checks,old_differences,old_max,official_max);
  $finish;
 end
endmodule
''')

def run(tool, *args, tag=''):
    with (out/(tag+tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,
                       stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvhdl','-work','original','original_TMDSEncoder.vhd',tag='original_')
run('xvhdl','-work','upstream','DVI_Constants.vhd','TMDS_Encoder.vhd',tag='official_')
run('xvhdl','-work','patched','patched_TMDSEncoder.vhd',tag='working_')
run('xvhdl','encoder_comparison.vhd',tag='comparison_')
run('xvlog','-sv','tb_encoder_comparison.sv')
run('xelab','-L','original','-L','upstream','-L','patched','tb_encoder_comparison','-s','comparison','-debug','typical')
(out/'run.tcl').write_text('run all\nquit\n')
run('xsim','comparison','-tclbatch','run.tcl','-log','comparison.log')
log=(out/'comparison.log').read_text()
assert 'PASS HDMI_ENCODER_AUDIT' in log and 'Fatal:' not in log
print('\n'.join(line for line in log.splitlines() if line.startswith(('PASS ','ORIGINAL_DIFFERENCE'))))
