`timescale 1ns/1ps
// 8250 register-layout polling console, 8N1 only. Programmable 16x divisor,
// 1024-byte RX queue, one TX shifter. No IRQ/modem/parity/full 16550 FIFO ABI.
module uart8250_poll #(parameter logic [15:0] RESET_DIVISOR=16'd27) (
    input logic clk,reset_n,
    input logic valid,store,
    input logic [2:0] address,
    input logic [31:0] write_data,
    input logic [3:0] mask,
    output wire ready,
    output logic [31:0] read_data,
    input logic rx,
    output wire tx
);
    logic [7:0] dll,dlm,lcr,mcr,scratch;
    logic [9:0] tx_shift;
    logic [3:0] tx_bits;
    logic [19:0] tx_count,tx_period;
    wire [19:0] bit_clocks={dlm,dll}==0?20'd16:{dlm,dll,4'b0};
    wire tx_write=store && address[2]==0 && mask[0] && !lcr[7];
    assign ready=!tx_write || tx_bits==0;
    assign tx=tx_bits==0?1'b1:tx_shift[0];
    wire accept=valid && ready;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic rx_meta,rx_sync;
    logic [1:0] rx_state;
    logic [19:0] rx_count,rx_period;
    logic [2:0] rx_bit;
    logic [7:0] rx_byte;
    logic [7:0] fifo[1024];
    logic [9:0] read_ptr,write_ptr;
    logic [10:0] count;
    logic overrun,frame_error;
    wire pop=accept && !store && !address[2] && mask[0] && !lcr[7] && count!=0;
    wire arrival=rx_state==3 && rx_count==0;
    wire push=arrival && (count<1024 || pop);
    wire reset_rx=accept && store && !address[2] && mask[2] && write_data[17];
    wire clear_errors=accept && !store && address[2] && mask[1];
    function automatic logic [7:0] reg_value(input logic [2:0] regno);
        case(regno)
            0: return lcr[7]?dll:(count!=0?fifo[read_ptr]:8'b0);
            1: return lcr[7]?dlm:8'b0; // interrupts not implemented
            2: return 8'h01; // no interrupt, no advertised 16550 FIFO
            3: return lcr;
            4: return mcr;
            5: return {1'b0,{2{tx_bits==0}},1'b0,frame_error,1'b0,overrun,count!=0};
            6: return 8'hb0; // fixed CTS/DSR/DCD; no modem flow control
            7: return scratch;
        endcase
    endfunction
    always_comb for(int n=0;n<4;n++) read_data[n*8+:8]=reg_value({address[2],2'b0}+3'(n));
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            dll<=RESET_DIVISOR[7:0]; dlm<=RESET_DIVISOR[15:8]; lcr<=3; mcr<=0; scratch<=0;
            tx_shift<='1; tx_bits<=0; tx_count<=0; tx_period<=16;
            rx_meta<=1; rx_sync<=1; rx_state<=0; rx_count<=0; rx_period<=16; rx_bit<=0; rx_byte<=0;
            read_ptr<=0; write_ptr<=0; count<=0; overrun<=0; frame_error<=0;
        end else begin
            rx_meta<=rx; rx_sync<=rx_meta;
            if(accept && store) begin
                if(!address[2]) begin
                    if(mask[0] && lcr[7]) dll<=write_data[7:0];
                    if(mask[1] && lcr[7]) dlm<=write_data[15:8];
                    if(mask[3]) lcr<={write_data[31],5'b0,2'b11}; // DLAB + fixed 8N1
                end else begin
                    if(mask[0]) mcr<=write_data[7:0]&8'h03;
                    if(mask[3]) scratch<=write_data[31:24];
                end
            end
            if(tx_bits==0) begin
                if(accept && tx_write) begin
                    tx_shift<={1'b1,write_data[7:0],1'b0}; tx_bits<=10;
                    tx_period<=bit_clocks; tx_count<=bit_clocks-1'b1;
                end
            end else if(tx_count==0) begin
                tx_shift<={1'b1,tx_shift[9:1]}; tx_bits<=tx_bits-1'b1; tx_count<=tx_period-1'b1;
            end else tx_count<=tx_count-1'b1;
            case(rx_state)
                0: if(!rx_sync) begin rx_state<=1; rx_period<=bit_clocks; rx_count<=(bit_clocks>>1)-1'b1; end
                1: if(rx_count!=0) rx_count<=rx_count-1'b1;
                   else if(rx_sync) rx_state<=0;
                   else begin rx_state<=2; rx_bit<=0; rx_count<=rx_period-1'b1; end
                2: if(rx_count!=0) rx_count<=rx_count-1'b1;
                   else begin
                       rx_byte[rx_bit]<=rx_sync; rx_count<=rx_period-1'b1;
                       if(rx_bit==7) rx_state<=3; else rx_bit<=rx_bit+1'b1;
                   end
                3: if(rx_count!=0) rx_count<=rx_count-1'b1; else rx_state<=0;
            endcase
            if(clear_errors) begin overrun<=0; frame_error<=0; end
            if(arrival && !rx_sync) frame_error<=1;
            if(arrival && !push) overrun<=1;
            if(pop) read_ptr<=read_ptr+1'b1;
            if(push) begin fifo[write_ptr]<=rx_byte; write_ptr<=write_ptr+1'b1; end
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: begin end
            endcase
            if(reset_rx) begin count<=0; read_ptr<=0; write_ptr<=0; overrun<=0; frame_error<=0; end
        end
    end
endmodule
