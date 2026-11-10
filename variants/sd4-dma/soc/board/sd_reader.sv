// Read-only SDHC/SDXC SPI master, mode 0. clk is the 100 MHz MIG UI clock.
module sd_reader #(parameter int INIT_HALF=128, FAST_HALF=8)(
    input wire clk,reset,enable,request,
    input wire [31:0] lba,
    output wire ready,valid, input wire take, output logic [7:0] data,
    output wire complete,failed,
    output logic sd_dclk,sd_mosi, output wire sd_ncs,input wire sd_miso
);
    typedef enum logic [3:0] {WAIT_ENABLE,CLOCKS,GAP,COMMAND,R1,EXTENSION,
        IDLE,TOKEN,DATA_BYTE,OFFER,CRC_HIGH,CRC_LOW,BLOCK_END,ERROR} state_t;
    state_t state;
    logic [5:0] cmd;
    logic [31:0] arg,extension;
    logic [3:0] index_byte;
    logic [15:0] attempts;
    logic [19:0] polls;
    logic fast;
    logic [8:0] pos;
    logic [15:0] crc;
    logic [7:0] crc_high;
    logic busy,byte_done;
    logic [7:0] tx,rx,divider;
    logic [2:0] bit_index;
    (* ASYNC_REG="TRUE" *) logic [1:0] miso_sync;
    always_ff @(posedge clk) miso_sync<={miso_sync[0],sd_miso};
    wire active_byte=state inside {CLOCKS,GAP,COMMAND,R1,EXTENSION,TOKEN,DATA_BYTE,CRC_HIGH,CRC_LOW};
    assign sd_ncs=state inside {WAIT_ENABLE,CLOCKS,GAP,IDLE,BLOCK_END,ERROR};
    assign ready=state==IDLE;
    assign valid=state==OFFER;
    assign complete=state==BLOCK_END;
    assign failed=state==ERROR;
    always_comb begin
        tx=8'hff;
        if(state==COMMAND) case(index_byte)
            0:tx={2'b01,cmd};
            1:tx=arg[31:24]; 2:tx=arg[23:16]; 3:tx=arg[15:8]; 4:tx=arg[7:0];
            default:tx=cmd==0 ? 8'h95 : cmd==8 ? 8'h87 : 8'h01;
        endcase
    end
    wire [7:0] half_period=fast ? 8'(FAST_HALF-1) : 8'(INIT_HALF-1);
    always_ff @(posedge clk) begin
        if(reset) begin
            sd_dclk<=0; sd_mosi<=1; busy<=0; byte_done<=0; divider<=0; bit_index<=7; rx<=0;
        end else begin
            byte_done<=0;
            if(!busy && !byte_done && active_byte) begin
                busy<=1; divider<=half_period; bit_index<=7; sd_mosi<=tx[7];
            end else if(busy && divider!=0) divider<=divider-1'b1;
            else if(busy) begin
                divider<=half_period; sd_dclk<=!sd_dclk;
                if(!sd_dclk) rx<={rx[6:0],miso_sync[1]};
                else if(bit_index==0) begin busy<=0; byte_done<=1; sd_mosi<=1; end
                else begin bit_index<=bit_index-1'b1; sd_mosi<=tx[bit_index-1'b1]; end
            end
        end
    end
    function automatic [15:0] crc16(input logic [15:0] old_crc,input logic [7:0] octet);
        logic [15:0] c;
        c=old_crc^{octet,8'h00};
        for(int i=0;i<8;i++) c={c[14:0],1'b0}^(c[15] ? 16'h1021 : 16'b0);
        return c;
    endfunction
    task automatic command(input logic [5:0] number,input logic [31:0] argument);
        cmd<=number; arg<=argument; index_byte<=0; polls<=0; state<=GAP;
    endtask
    wire [31:0] response={extension[23:0],rx};
    always_ff @(posedge clk) begin
        if(reset) begin
            state<=WAIT_ENABLE; index_byte<=0; attempts<=0; fast<=0;
            cmd<=0; arg<=0; polls<=0; extension<=0; pos<=0; crc<=0; data<=0; crc_high<=0;
        end else case(state)
            WAIT_ENABLE: if(enable) state<=CLOCKS;
            CLOCKS: if(byte_done) begin
                if(index_byte==9) command(0,0); else index_byte<=index_byte+1'b1;
            end
            GAP: if(byte_done) state<=COMMAND;
            COMMAND: if(byte_done) begin
                if(index_byte==5) begin state<=R1; index_byte<=0; end
                else index_byte<=index_byte+1'b1;
            end
            R1: if(byte_done) begin
                if(rx[7]) begin
                    if(polls==15) state<=ERROR; else polls<=polls+1'b1;
                end else case(cmd)
                    0: if(rx==1) command(8,32'h1aa); else state<=ERROR;
                    8,58: if(rx==(cmd==8 ? 1 : 0)) state<=EXTENSION; else state<=ERROR;
                    55: if(rx<=1) command(41,32'h40000000); else state<=ERROR;
                    41: if(rx==0) command(58,0);
                        else if(rx==1 && attempts<8192) begin attempts<=attempts+1'b1; command(55,0); end
                        else state<=ERROR;
                    17: if(rx==0) begin state<=TOKEN; polls<=0; end else state<=ERROR;
                    default: state<=ERROR;
                endcase
            end
            EXTENSION: if(byte_done) begin
                extension<=response;
                if(index_byte!=3) index_byte<=index_byte+1'b1;
                else if(cmd==8 && response==32'h1aa) command(55,0);
                else if(cmd==58 && response[31:30]==2'b11 && |response[23:15]) begin fast<=1; state<=IDLE; end
                else state<=ERROR;
            end
            IDLE: if(request) command(17,lba);
            TOKEN: if(byte_done) begin
                if(rx==8'hfe) begin pos<=0; crc<=0; state<=DATA_BYTE; end
                else if(rx!=8'hff || &polls) state<=ERROR;
                else polls<=polls+1'b1;
            end
            DATA_BYTE: if(byte_done) begin data<=rx; crc<=crc16(crc,rx); state<=OFFER; end
            OFFER: if(take) begin pos<=pos+1'b1; state<=(&pos) ? CRC_HIGH : DATA_BYTE; end
            CRC_HIGH: if(byte_done) begin crc_high<=rx; state<=CRC_LOW; end
            CRC_LOW: if(byte_done) state<=({crc_high,rx}==crc) ? BLOCK_END : ERROR;
            BLOCK_END: state<=IDLE;
            default: state<=ERROR;
        endcase
    end
endmodule
