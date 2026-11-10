// Sector counts and CRC32s are little-endian. MIG addresses are in 32-bit words.
module sd_boot #(parameter int RAM_BYTES=1024*1024*1024, INIT_HALF=128, FAST_HALF=8)(
    input wire clk,reset,calibrated,app_rdy,app_wdf_rdy,rd_valid,
    input wire [255:0] rd_data,
    output wire en,write_cmd,wdf_en, output wire [28:0] addr,output wire [255:0] wdata,
    output wire done,failed,
    output wire enable,request,output logic [31:0] lba,
    input wire card_ready,valid,complete,card_bad,input wire [7:0] data,output wire take
);
    typedef enum logic [3:0] {WAIT_CAL,CLEAR,REQUEST,RECEIVE,PUT,GET,CHECK,COMPARE,
        SECTOR_END,HEADER,START_SEG,FINISH,ERROR} state_t;
    state_t state;
    logic [28:0] clear_addr,line_addr;
    logic [255:0] line,header;
    logic [7:0] equal_parts;
    logic [31:0] sectors_left,crc,expected_crc;
    logic [8:0] pos;
    logic [1:0] segment;
    logic reading_header,block_seen;
    assign enable=state==REQUEST;
    assign request=state==REQUEST;
    assign take=state==RECEIVE;
    wire accept_write=(state==CLEAR || state==PUT) && app_rdy && app_wdf_rdy;
    assign wdf_en=accept_write;
    assign en=accept_write || state==GET;
    assign write_cmd=state!=GET;
    assign addr=state==CLEAR ? clear_addr : line_addr;
    assign wdata=state==CLEAR ? 256'b0 : line;
    assign done=state==FINISH;
    assign failed=state==ERROR;
    function automatic [31:0] crc32(input logic [31:0] old_crc,input logic [7:0] octet);
        logic [31:0] c;
        c=old_crc^{24'b0,octet};
        for(int i=0;i<8;i++) c=(c>>1)^(c[0] ? 32'hedb88320 : 32'b0);
        return c;
    endfunction
    wire [31:0] fw_count=header[95:64],kernel_count=header[159:128],dt_count=header[223:192];
    always_ff @(posedge clk) begin
        if(reset) begin
            state<=WAIT_CAL; clear_addr<=0; lba<=2048; reading_header<=1;
            segment<=0; pos<=0; block_seen<=0; line_addr<=0;
        end else if(card_bad) state<=ERROR;
        else begin
            if(complete) block_seen<=1;
            case(state)
                WAIT_CAL: if(calibrated) state<=CLEAR;
                CLEAR: if(accept_write) begin
                    if(clear_addr==29'((RAM_BYTES-32)/4)) state<=REQUEST;
                    else clear_addr<=clear_addr+8;
                end
                REQUEST: if(card_ready) begin block_seen<=0; pos<=0; state<=RECEIVE; end
                RECEIVE: if(valid) begin
                    pos<=pos+1'b1;
                    if(reading_header) begin
                        if(pos<32) header<={data,header[255:8]};
                        if(&pos) state<=SECTOR_END;
                    end else begin
                        line<={data,line[255:8]}; crc<=crc32(crc,data);
                        if(&pos[4:0]) state<=PUT;
                    end
                end
                PUT: if(accept_write) state<=GET;
                GET: if(app_rdy) state<=CHECK;
                CHECK: if(rd_valid) begin
                    for(int i=0;i<8;i++) equal_parts[i]<=rd_data[32*i+:32]==line[32*i+:32];
                    state<=COMPARE;
                end
                COMPARE: if(&equal_parts) begin
                    line_addr<=line_addr+8; state<=pos==0 ? SECTOR_END : RECEIVE;
                end else state<=ERROR;
                SECTOR_END: if(block_seen) begin
                    lba<=lba+1'b1;
                    if(reading_header) state<=HEADER;
                    else if(sectors_left!=1) begin sectors_left<=sectors_left-1'b1; state<=REQUEST; end
                    else if(~crc!=expected_crc) state<=ERROR;
                    else if(segment==2) state<=FINISH;
                    else begin segment<=segment+1'b1; state<=START_SEG; end
                end
                HEADER: if(header[63:0]==64'h313030445359524f &&
                    fw_count!=0 && fw_count<=8192 && kernel_count!=0 && kernel_count<=251904 &&
                    dt_count!=0 && dt_count<=2048) begin reading_header<=0; state<=START_SEG; end
                    else state<=ERROR;
                START_SEG: begin
                    case(segment)
                        0:begin line_addr<=0; sectors_left<=fw_count; expected_crc<=header[127:96]; end
                        1:begin line_addr<=29'h100000; sectors_left<=kernel_count; expected_crc<=header[191:160]; end
                        default:begin line_addr<=29'h1fc0000; sectors_left<=dt_count; expected_crc<=header[255:224]; end
                    endcase
                    crc<='1; state<=REQUEST;
                end
                FINISH: state<=FINISH;
                default: state<=ERROR;
            endcase
        end
    end
endmodule
