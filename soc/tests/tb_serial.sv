`timescale 1ns/1ps
module tb_serial;
    import or_bo_axi_pkg::*;
    logic clk=0,reset_n=0;always #5 clk=~clk;
    al_req_t q[3];al_rsp_t p[3];
    wire utx,sck,mosi,cs_n,scl_t,sda_t;logic miso=0,slave_scl=1,slave_sda=1;
    wire scl=scl_t && slave_scl,sda=sda_t && slave_sda;
    int checks=0;logic [31:0] data;
    gen3_axi_uart u(.clk,.reset_n,.rx(utx),.tx(utx),.req(q[0]),.rsp(p[0]));
    gen3_axi_spi s(.clk,.reset_n,.miso,.mosi,.sck,.cs_n,.req(q[1]),.rsp(p[1]));
    gen3_axi_i2c i(.clk,.reset_n,.scl_i(scl),.sda_i(sda),.scl_t,.sda_t,.req(q[2]),.rsp(p[2]));
    initial begin #20000000;$fatal(1,"serial timeout");end
    task automatic tick;@(negedge clk);endtask
    task automatic wr(input int n,input int addr,input logic [31:0] value,input logic [3:0] strb=15,input int order=0,input logic [1:0] response=OKAY);
        bit ah,wh;int age;logic [1:0] saved;
        ah=0;wh=0;age=0;tick();q[n]='0;q[n].awaddr=32'(addr);q[n].wdata=value;q[n].wstrb=strb;
        while(!ah || !wh) begin
            q[n].awvalid=!ah && (order!=1 || age>=3);q[n].wvalid=!wh && (order!=2 || age>=3);
            @(posedge clk);if(q[n].awvalid && p[n].awready) ah=1;if(q[n].wvalid && p[n].wready) wh=1;
            tick();age++;
        end
        q[n].awvalid=0;q[n].wvalid=0;
        while(!p[n].bvalid) tick();saved=p[n].bresp;
        repeat(4) begin tick();assert(p[n].bvalid && p[n].bresp==saved) else $fatal(1,"B unstable");end
        assert(saved==response) else $fatal(1,"B n=%d addr=%h got=%h want=%h",n,addr,saved,response);
        q[n].bready=1;tick();q[n]='0;checks++;
    endtask
    task automatic rd(input int n,input int addr,output logic [31:0] value,input logic [3:0] mask=15,input logic [1:0] response=OKAY);
        tick();q[n]='0;q[n].araddr=32'(addr);q[n].rmask=mask;q[n].arvalid=1;
        do @(posedge clk);while(!p[n].arready);
        tick();q[n].arvalid=0;while(!p[n].rvalid) tick();value=p[n].rdata;
        repeat(4) begin tick();assert(p[n].rvalid && p[n].rdata==value && p[n].rresp==response) else $fatal(1,"R unstable/error");end
        q[n].rready=1;tick();q[n]='0;checks++;
    endtask
    task automatic done_io(input int n,output logic [31:0] value);
        for(int k=0;k<2000;k++) begin rd(n,4,value);if(value[1] && !value[0]) return;end
        $fatal(1,"serial completion timeout n=%d",n);
    endtask
    task automatic uart_monitor(input logic [7:0] expected);
        @(negedge utx);repeat(8) @(posedge clk);assert(!utx) else $fatal(1,"UART start");
        for(int b=0;b<8;b++) begin repeat(16) @(posedge clk);assert(utx==expected[b]) else $fatal(1,"UART data bit %d",b);end
        repeat(16) @(posedge clk);assert(utx) else $fatal(1,"UART stop");
    endtask
    task automatic spi_slave(input bit pol,phase,input logic [7:0] expected,reply_byte);
        int b;logic level;b=0;miso=reply_byte[7];@(negedge cs_n);
        for(int e=0;e<16;e++) begin
            @(sck);level=sck;assert(level==(e[0]?pol:!pol)) else $fatal(1,"SPI clock mode");
            if(e[0]==phase) begin assert(mosi==expected[7-b]) else $fatal(1,"SPI MOSI mode=%d%d bit=%d",pol,phase,b);b++;end
            else if(b<8) miso=reply_byte[7-b];
        end
        assert(b==8) else $fatal(1,"SPI edges");
    endtask
    task automatic i2c_start;
        do @(negedge sda);while(!scl);
    endtask
    task automatic i2c_stop;
        do @(posedge sda);while(!scl);
    endtask
    task automatic i2c_get(input logic [7:0] expected,input bit ack);
        logic [7:0] byte_value;
        for(int b=7;b>=0;b--) begin @(posedge scl);byte_value[b]=sda;end
        assert(byte_value==expected) else $fatal(1,"I2C write got=%h expected=%h",byte_value,expected);
        @(negedge scl);slave_sda=!ack;@(posedge scl);@(negedge scl);slave_sda=1;
    endtask
    task automatic i2c_send(input logic [7:0] value,input bit expect_nack);
        for(int b=7;b>=0;b--) begin slave_sda=value[b];@(posedge scl);@(negedge scl);end
        slave_sda=1;@(posedge scl);assert(sda==expect_nack) else $fatal(1,"I2C read ACK");@(negedge scl);
    endtask
    initial begin
        for(int n=0;n<3;n++) q[n]='0;
        repeat(6) tick();reset_n=1;repeat(6) tick();
        // Packed 8250, byte enables and both AW/W arrival orders.
        wr(0,0,32'h80000000,8,1);wr(0,0,1,3,2);wr(0,0,32'h03000000,8);
        wr(0,4,32'hc3000000,8);rd(0,4,data,8);assert(data[31:24]==8'hc3) else $fatal(1,"UART scratch");
        fork uart_monitor(8'ha6);wr(0,0,32'ha6,1,1);join
        repeat(30) tick();rd(0,4,data,2);assert(data[8]) else $fatal(1,"UART RX missing");
        rd(0,0,data,1);assert(data[7:0]==8'ha6) else $fatal(1,"UART RX byte");
        rd(0,4,data,2);assert(!data[8]) else $fatal(1,"UART read side effect repeated");
        // Start acceptance precedes serial completion. Modes tested against independent slave.
        wr(1,8,32'habcd,3);wr(1,8,32'h1200,2);rd(1,8,data);assert(data==32'h12cd) else $fatal(1,"SPI byte enable");
        wr(1,8,16,3,2);wr(1,0,8'h96,1);
        for(int mode=0;mode<4;mode++) begin
            wr(1,12,32'(mode),1);
            fork spi_slave(mode[0],mode[1],8'h96,8'h3c);wr(1,16,1,1,1);join
            done_io(1,data);assert(cs_n && sck==mode[0]) else $fatal(1,"SPI idle");
            rd(1,0,data);assert(data==8'h3c) else $fatal(1,"SPI RX");
        end
        wr(1,12,4,1);assert(!cs_n) else $fatal(1,"SPI CS hold");wr(1,12,0,1);
        wr(1,8,200,3);wr(1,16,1,1);wr(1,16,1,1,0,SLVERR);wr(1,8,8,3,0,SLVERR);done_io(1,data);
        rd(1,24,data,15,SLVERR);wr(1,0,8'hff,0); // WSTRB=0 has no effect.
        // ACK write, repeated START, read NACK+STOP, real open-drain slave.
        wr(2,8,12,3);wr(2,0,8'ha0,1);
        fork
            begin i2c_start();i2c_get(8'ha0,1);end
            begin wr(2,16,9,1);done_io(2,data);assert((data&63)==34) else $fatal(1,"I2C write status %h",data);end
        join
        wr(2,0,8'ha1,1);
        fork
            begin i2c_start();i2c_get(8'ha1,1);end
            begin wr(2,16,9,1);done_io(2,data);assert((data&31)==2) else $fatal(1,"I2C repeated START");end
        join
        fork
            begin i2c_send(8'h69,1);i2c_stop();end
            begin wr(2,16,22,1);done_io(2,data);assert((data&63)==2) else $fatal(1,"I2C read status");end
        join
        rd(2,0,data);assert(data==8'h69) else $fatal(1,"I2C read data %h",data);
        // Two-byte read: master ACK continues the transaction, final NACK ends it.
        wr(2,0,8'ha1,1);
        fork
            begin i2c_start();i2c_get(8'ha1,1);end
            begin wr(2,16,9,1);done_io(2,data);end
        join
        fork
            i2c_send(8'h12,0);
            begin wr(2,16,4,1);done_io(2,data);end
        join
        rd(2,0,data);assert(data==8'h12) else $fatal(1,"I2C first read");
        fork
            begin i2c_send(8'h34,1);i2c_stop();end
            begin wr(2,16,22,1);done_io(2,data);end
        join
        rd(2,0,data);assert(data==8'h34) else $fatal(1,"I2C second read");
        // Slave stretch then ACK; separate command without a slave must NACK.
        wr(2,0,8'h50,1);
        fork
            begin i2c_start();@(negedge scl);slave_scl=0;
                fork
                    begin repeat(60) tick();slave_scl=1;end
                    begin i2c_get(8'h50,1);i2c_stop();end
                join
            end
            begin wr(2,16,11,1);done_io(2,data);assert((data&63)==2) else $fatal(1,"I2C stretch");end
        join
        wr(2,16,11,1);done_io(2,data);assert((data&63)==6) else $fatal(1,"I2C NACK");
        wr(2,12,200,15);slave_scl=0;wr(2,16,1,1);
        wr(2,16,1,1,0,SLVERR);wr(2,8,50,3,0,SLVERR);done_io(2,data);
        assert((data&63)==10 && scl_t && sda_t) else $fatal(1,"I2C stretch timeout/release");slave_scl=1;
        repeat(5) tick();wr(2,16,12,1,0,SLVERR); // simultaneous READ/WRITE rejected
        slave_sda=0;wr(2,16,1,1);done_io(2,data);assert((data&63)==18) else $fatal(1,"I2C occupied bus");slave_sda=1;
        wr(2,0,8'hff,1);
        fork
            begin i2c_start();@(negedge scl);slave_sda=0;end
            begin wr(2,16,11,1);done_io(2,data);assert((data&63)==18 && scl_t && sda_t) else $fatal(1,"I2C arbitration loss release");end
        join
        slave_sda=1;
        wr(2,16,32,1);rd(2,4,data);assert((data&63)==0) else $fatal(1,"I2C sticky clear");
        $display("PASS AXI_SERIAL checks=%0d UART=8N1 SPI=modes0to3 I2C=ACK,NACK,restart,read,stretch,timeout,bus_busy AXI=AW_W_order,B_R_stall,WSTRB",checks);$finish;
    end
endmodule
