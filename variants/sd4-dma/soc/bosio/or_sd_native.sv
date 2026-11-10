// Native SD command/data PHY. One transaction, 1/4-bit, 1..512 bytes.
// Clock is generated from clk with a clock-enable; no internal SD clock domain.
// Buffer ownership remains with the caller except while busy. CRC failures never
// publish successful data. Reset must not cancel an outstanding AXI transaction.
module or_sd_native # (parameter int TIMEOUT_CYCLES=100000000) (
 input wire clk,reset_n,start,
 input wire [5:0] command,input wire [31:0] argument,
 input wire [1:0] response_type, // 0 none, 1 R1/R3/R6/R7, 2 R2, 3 R1b
 input wire check_crc,four_bit,data_present,data_write,
 input wire [9:0] data_bytes,input wire [15:0] half_period,
 output wire busy,output logic done,output logic [2:0] error,
 output logic [127:0] response,
 input wire [8:0] buffer_address,input wire [7:0] buffer_wdata,
 input wire buffer_we,output wire [7:0] buffer_rdata,
 (* IOB="TRUE" *) output logic sd_clk,sd_cmd_o,sd_cmd_t,input wire sd_cmd_i,
 (* IOB="TRUE" *) output logic [3:0] sd_dat_o,
 output logic [3:0] sd_dat_t,input wire [3:0] sd_dat_i
);
 typedef enum logic [4:0] {IDLE,PREP,TX_CMD,WAIT_RSP,RX_RSP,RSP_END,
   WAIT_DATA,RX_DATA,RX_CRC,RX_END,TX_START,TX_DATA,TX_CRC,TX_END,
   WAIT_TOKEN,RX_TOKEN,WAIT_BUSY,GAP,FINISH} state_t;
 state_t state;
 (* ram_style="distributed" *) logic [7:0] buffer_mem[512];
 // One read address and one write address. Multiple conditional array writes
 // and bit-indexed reads otherwise expand this 512-byte buffer into thousands
 // of flip-flops/multiplexers in Vivado.
 wire [8:0] read_address=state==TX_DATA?byte_count[8:0]:buffer_address;
 wire [7:0] read_byte=buffer_mem[read_address];
 assign buffer_rdata=read_byte;
 logic [47:0] cmd_shift;
 logic [5:0] captured_command;
 logic [135:0] rsp_shift;
 logic [7:0] bit_count;
 logic [9:0] byte_count,length;
 logic [7:0] byte_shift;
 logic [2:0] subbit;
 logic [15:0] crc[4],received_crc[4],ticks,divider;
 logic [31:0] watchdog;
 logic [1:0] rt;
 logic crc_check,wide,has_data,write_data;
 logic [6:0] response_crc;
 logic [4:0] token;
 logic [4:0] gap_count;
 state_t after_gap;
 assign busy=state!=IDLE;
 wire edge_tick=ticks==0;
 wire rising=edge_tick && !sd_clk;
 wire falling=edge_tick && sd_clk;
 (* IOB="TRUE" *) logic cmd_sample;
 (* IOB="TRUE" *) logic [3:0] dat_sample;
 logic sample_enable,sample_tick;
 // The returned SD signal includes the forwarded clock's pad delay. Sample
 // 10ns after the internal SD rising edge (30ns after the preceding fall in
 // fast mode), then consume it one cycle later. This is before the next card
 // falling launch, with input setup/hold checked against the forwarded clock.
 always_ff @(posedge clk) begin
   if(sample_enable) begin cmd_sample<=sd_cmd_i;dat_sample<=sd_dat_i;end
   if(!reset_n) begin sample_enable<=0;sample_tick<=0;end
   else begin sample_enable<=rising;sample_tick<=sample_enable;end
 end
 function automatic [6:0] crc7(input [6:0] c,input bit b);
   return {c[5:0],1'b0} ^ ((c[6]^b)?7'h09:7'h00);
 endfunction
 function automatic [15:0] crc16(input [15:0] c,input bit b);
   return {c[14:0],1'b0} ^ ((c[15]^b)?16'h1021:16'h0000);
 endfunction
 function automatic [47:0] packet(input [5:0] cmd,input [31:0] arg);
   logic [39:0] prefix; logic [6:0] c;
   prefix={2'b01,cmd,arg};c=0;
   for(int i=39;i>=0;i--) c=crc7(c,prefix[i]);
   return {prefix,c,1'b1};
 endfunction
 wire receive_byte=state==RX_DATA && sample_tick && subbit==(wide?3'd1:3'd7);
 wire memory_write=reset_n && (receive_byte || (buffer_we && !busy));
 wire [8:0] write_address=receive_byte?byte_count[8:0]:buffer_address;
 wire [7:0] write_byte=receive_byte?(wide?{byte_shift[3:0],dat_sample}:{byte_shift[6:0],dat_sample[0]}):buffer_wdata;
 always_ff @(posedge clk) if(memory_write) buffer_mem[write_address]<=write_byte;
 always_ff @(posedge clk) begin
   if(!reset_n) begin
     state<=IDLE;sd_clk<=0;sd_cmd_o<=1;sd_cmd_t<=1;sd_dat_o<=15;sd_dat_t<=15;
     done<=0;error<=0;response<=0;ticks<=124;divider<=125;watchdog<=0;
     cmd_shift<=0;captured_command<=0;rsp_shift<=0;bit_count<=0;byte_count<=0;byte_shift<=0;subbit<=0;
     rt<=0;crc_check<=0;wide<=0;has_data<=0;write_data<=0;length<=0;
     response_crc<=0;token<=0;gap_count<=0;after_gap<=FINISH;
     for(int i=0;i<4;i++) begin crc[i]<=0;received_crc[i]<=0;end
   end else begin
     done<=0;
     if(ticks!=0) ticks<=ticks-1'b1;
     else begin ticks<=divider-1'b1;sd_clk<=!sd_clk;end
     if(state!=IDLE) watchdog<=watchdog+1'b1;else watchdog<=0;
     if(falling && (state==IDLE || state==FINISH)) begin sd_cmd_t<=1;sd_dat_t<=15;end
     if(state!=IDLE && watchdog==TIMEOUT_CYCLES-1) begin
       error<=1;state<=FINISH;
     end else case(state)
       IDLE: if(start) begin
         cmd_shift<=packet(command,argument);captured_command<=command;rt<=response_type;crc_check<=check_crc;
         wide<=four_bit;has_data<=data_present;write_data<=data_write;length<=data_bytes;
         divider<=half_period<2?16'd2:half_period;error<=0;response<=0;
         byte_count<=0;subbit<=0;byte_shift<=0;rsp_shift<=0;response_crc<=0;
         for(int i=0;i<4;i++) begin crc[i]<=0;received_crc[i]<=0;end
         if(data_present && (data_bytes==0 || data_bytes>512)) begin error<=4;state<=FINISH;end
         else state<=PREP;
       end
       PREP: if(falling) begin sd_dat_t<=15;sd_cmd_t<=0;sd_cmd_o<=cmd_shift[47];bit_count<=47;state<=TX_CMD;end
       TX_CMD: if(falling) begin
         if(bit_count==0) begin
           sd_cmd_t<=1;
           if(rt==0) begin gap_count<=8;after_gap<=FINISH;state<=GAP;end
           else state<=WAIT_RSP;
         end else begin cmd_shift<={cmd_shift[46:0],1'b1};sd_cmd_o<=cmd_shift[46];bit_count<=bit_count-1'b1;end
       end
       WAIT_RSP: if(sample_tick && !cmd_sample) begin
         rsp_shift<=0;bit_count<=rt==2?8'd134:8'd46;response_crc<=0;state<=RX_RSP;
       end
       RX_RSP: if(sample_tick) begin
         rsp_shift<={rsp_shift[134:0],cmd_sample};
         if(bit_count>=8 && (rt!=2 || bit_count<128)) response_crc<=crc7(response_crc,cmd_sample);
         if(bit_count==0) state<=RSP_END;else bit_count<=bit_count-1'b1;
       end
       RSP_END: begin
         response<=rt==2?rsp_shift[127:0]:{96'b0,rsp_shift[39:8]};
         if(!rsp_shift[0] || (rt==2?rsp_shift[134]:rsp_shift[46]) ||
            (crc_check && (response_crc!=rsp_shift[7:1] || (rt!=2 && rsp_shift[45:40]!=captured_command)))) begin error<=2;state<=FINISH;end
         else if(has_data) begin
           if(write_data) begin gap_count<=8;after_gap<=TX_START;state<=GAP;end
           else state<=WAIT_DATA;
         end else if(rt==3) begin gap_count<=2;after_gap<=WAIT_BUSY;state<=GAP;end
         else begin gap_count<=8;after_gap<=FINISH;state<=GAP;end
       end
       WAIT_DATA: if(sample_tick && !dat_sample[0]) begin
         if(wide && dat_sample!=0) begin error<=3;state<=FINISH;end
         else state<=RX_DATA;
       end
       RX_DATA: if(sample_tick) begin
         byte_shift<=wide?{byte_shift[3:0],dat_sample}:{byte_shift[6:0],dat_sample[0]};
         for(int i=0;i<4;i++) if(wide || i==0) crc[i]<=crc16(crc[i],dat_sample[i]);
         if(subbit==(wide?3'd1:3'd7)) begin
           subbit<=0;byte_count<=byte_count+1'b1;
           if(byte_count==length-1'b1) begin bit_count<=15;state<=RX_CRC;end
         end else subbit<=subbit+1'b1;
       end
       RX_CRC: if(sample_tick) begin
         for(int i=0;i<4;i++) received_crc[i]<={received_crc[i][14:0],dat_sample[i]};
         if(bit_count==0) state<=RX_END;else bit_count<=bit_count-1'b1;
       end
       RX_END: if(sample_tick) begin
         for(int i=0;i<4;i++) if((wide || i==0) && (crc[i]!=received_crc[i] || !dat_sample[i])) error<=3;
         gap_count<=8;after_gap<=FINISH;state<=GAP;
       end
       TX_START: if(falling) begin sd_dat_t<=0;sd_dat_o<=wide?4'h0:4'he;state<=TX_DATA;end
       TX_DATA: if(falling) begin
         for(int i=0;i<4;i++) begin
           sd_dat_o[i]<=wide?read_byte[(subbit==0?4:0)+i]:(i==0?read_byte[7-subbit]:1'b1);
           if(wide || i==0) crc[i]<=crc16(crc[i],wide?read_byte[(subbit==0?4:0)+i]:read_byte[7-subbit]);
         end
         if(subbit==(wide?3'd1:3'd7)) begin
           subbit<=0;byte_count<=byte_count+1'b1;
           if(byte_count==length-1'b1) begin bit_count<=15;state<=TX_CRC;end
         end else subbit<=subbit+1'b1;
       end
       TX_CRC: if(falling) begin
         for(int i=0;i<4;i++) sd_dat_o[i]<=(wide || i==0)?crc[i][bit_count[3:0]]:1'b1;
         if(bit_count==0) state<=TX_END;else bit_count<=bit_count-1'b1;
       end
       TX_END: if(falling) begin sd_dat_o<=15;gap_count<=1;after_gap<=WAIT_TOKEN;state<=GAP;end
       WAIT_TOKEN: begin
         if(falling) sd_dat_t<=15;
         if(sample_tick && !dat_sample[0]) begin token<=0;bit_count<=3;state<=RX_TOKEN;end
       end
       RX_TOKEN: if(sample_tick) begin
         token<={token[3:0],dat_sample[0]};
         if(bit_count==0) begin
           if({token[3:0],dat_sample[0]}!=5'b00101) error<=3;
           state<=WAIT_BUSY;
         end else bit_count<=bit_count-1'b1;
       end
       WAIT_BUSY: if(sample_tick && dat_sample[0]) begin gap_count<=8;after_gap<=FINISH;state<=GAP;end
       GAP: if(falling) begin if(gap_count==1) state<=after_gap;else gap_count<=gap_count-1'b1;end
       FINISH: begin done<=1;state<=IDLE;end
       default:state<=IDLE;
     endcase
   end
 end
 // synthesis translate_off
 logic was_reset=1,was_falling=0;
 logic [9:0] previous_outputs;
 always @(posedge clk) begin
   if(reset_n && !was_reset && {sd_cmd_o,sd_cmd_t,sd_dat_o,sd_dat_t}!=previous_outputs)
     assert(was_falling) else $fatal(1,"SD output/OE changed outside falling phase");
   previous_outputs<={sd_cmd_o,sd_cmd_t,sd_dat_o,sd_dat_t};
   was_reset<=!reset_n;was_falling<=falling;
 end
 // synthesis translate_on
endmodule
