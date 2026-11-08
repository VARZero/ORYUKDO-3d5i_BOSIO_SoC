`timescale 1ns/1ps
module tb_axi_fabric;
    import or_bo_axi_pkg::*;
    logic clk=0,cpu_clk=0,reset_n=0;
    always #5 clk=~clk;
    // Deliberately unrelated clocks (not just a phase-aligned divide-by-two).
    always #13 cpu_clk=~cpu_clk;
    ax_req_t cpu_req,masters[4],memory;ax_rsp_t cpu_rsp,replies[4],memory_reply;
    al_req_t lite[LITE_PORTS];al_rsp_t lite_rsp[LITE_PORTS];
    logic lock_request=0;wire lock_grant,snoop_valid,snoop_ready,inv;
    wire [31:0] snoop_address,inv_address;
    int checks=0,snoops=0,cycles=0;logic [31:0] last_snoop;
    wire [1:0] active_master;wire busy;
    wire sensor_enable,tx,timer_irq;wire [63:0] timer_time;
    or_bo_axi_cdc cross_cpu(.reset_n,.s_clk(cpu_clk),.s_reset_n(reset_n),.m_clk(clk),.m_reset_n(reset_n),
        .s_req(cpu_req),.s_rsp(cpu_rsp),.m_req(masters[0]),.m_rsp(replies[0]));
    or_bo_xpm_mailbox #(32) snoop(.reset_n,.s_clk(clk),.s_reset_n(reset_n),.d_clk(cpu_clk),.d_reset_n(reset_n),
        .s_data(snoop_address),.s_valid(snoop_valid),.s_ready(snoop_ready),.d_data(inv_address),.d_valid(inv),.d_ready(1'b1));
    or_bo_axi_fabric dut(.lite_reply(lite_rsp),.*);
    axi_ram_model ram(.clk(clk),.reset_n(reset_n),.req(memory),.rsp(memory_reply));
    gen3_bosio_status status(.clk,.reset_n,.req(lite[0]),.rsp(lite_rsp[0]),
        .sensor_enable,.sensor_ready(1'b1),.sensor_error(1'b0),.projection_irq(2'b0));
    for(genvar n=1;n<LITE_PORTS;n++) axi_lite_test_slave #(n) endpoint(.clk(clk),.reset_n(reset_n),.req(lite[n]),.rsp(lite_rsp[n]));
    always @(posedge cpu_clk) if(reset_n && inv) begin snoops<=snoops+1;last_snoop<=inv_address;end
    always @(posedge clk) if(reset_n) begin cycles<=cycles+1;if(cycles>200000) $fatal(1,"Timeout");end
    task automatic tick(input int m);if(m==0) @(negedge cpu_clk);else @(negedge clk);endtask
    task automatic pos(input int m);if(m==0) @(posedge cpu_clk);else @(posedge clk);endtask
    function automatic ax_rsp_t response(input int m);return m==0?cpu_rsp:replies[m];endfunction
    task automatic set_request(input int m,input ax_req_t q);if(m==0) cpu_req=q;else masters[m]=q;endtask
    task automatic write_burst(input int m,input logic [63:0] a,input int count,input logic [31:0] value,
                               input logic [3:0] mask,input bit early_w,input logic [1:0] expected);
        ax_req_t q;ax_rsp_t s;bit ah,wh;int beat,age;
        q='0;q.aw.addr=a;q.aw.id=1;q.aw.len=8'(count-1);q.aw.size=2;q.aw.burst=1;
        tick(m);q.w.strb=mask;
        ah=0;wh=0;beat=0;age=0;
        while(!ah || beat<count) begin
            // Independent AW and W valid: do not wait for address READY to send W.
            q.awvalid=!ah && (!early_w || age>=3);
            q.wvalid=beat<count && (early_w || age>=2);
            q.w.data=value+32'(beat);q.w.last=beat==count-1;set_request(m,q);
            pos(m);s=response(m);wh=q.wvalid && s.wready;
            if(q.awvalid && s.awready) ah=1;
            tick(m);if(ah) q.awvalid=0;if(wh) beat++;age++;
        end
        q.wvalid=0;q.bready=0;set_request(m,q);
        repeat(3) tick(m);q.bready=1;set_request(m,q);
        do begin pos(m);s=response(m);if(!s.bvalid) tick(m);end while(!s.bvalid);
        assert(s.b.resp==expected && s.b.id==1) else $fatal(1,"B master=%0d addr=%h resp=%h expected=%h",m,a,s.b.resp,expected);
        tick(m);set_request(m,'0);checks++;
    endtask
    task automatic read_burst(input int m,input logic [63:0] a,input int count,input logic [31:0] expected_data,
                              input bit check_data,input logic [1:0] expected_resp,input logic [1:0] burst=1);
        ax_req_t q;ax_rsp_t s;
        q='0;q.ar.addr=a;q.ar.id=1;q.ar.len=8'(count-1);q.ar.size=2;q.ar.burst=burst;q.arvalid=1;
        tick(m);set_request(m,q);
        do begin pos(m);s=response(m);if(!s.arready) tick(m);end while(!s.arready);
        tick(m);q.arvalid=0;set_request(m,q);
        for(int n=0;n<count;n++) begin
            repeat(2) tick(m);q.rready=1;set_request(m,q);
            do begin pos(m);s=response(m);if(!s.rvalid) tick(m);end while(!s.rvalid);
            assert(s.r.resp==expected_resp && s.r.id==1 && s.r.last==(n==count-1)) else $fatal(1,"R framing addr=%h beat=%0d",a,n);
            if(check_data) assert(s.r.data==expected_data+32'(n)) else $fatal(1,"R data addr=%h got=%h expected=%h",a,s.r.data,expected_data+32'(n));
            tick(m);q.rready=0;set_request(m,q);
        end
        set_request(m,'0);checks++;
    endtask
    initial begin
        cpu_req='0;for(int n=1;n<4;n++) masters[n]='0;
        // XSIM glbl holds FPGA configuration GSR for the first 100 ns.
        // Keep system reset asserted after GSR release in both simulators.
        repeat(24) @(negedge clk);reset_n=1;
        for(int m=0;m<4;m++) begin
            write_burst(m,64'h80001000+64'(m*256),4,32'h12340000+32'(m*16),4'hf,m%2==0,OKAY);
            read_burst(m,64'h80001000+64'(m*256),4,32'h12340000+32'(m*16),1,OKAY);
        end
        write_burst(0,64'h80001000,1,32'h00ab00cd,4'b0101,1,OKAY);
        read_burst(0,64'h80001000,1,32'h12ab00cd,1,OKAY);
        read_burst(0,64'h80001000,16,0,0,OKAY,0);
        read_burst(0,64'h80001000,17,0,0,DECERR,0);
        read_burst(0,64'h80001000,4,0,0,DECERR,2); // WRAP is not supported.
        read_burst(0,64'h80008000,256,0,0,OKAY); // Maximum legal INCR burst.
        read_burst(0,64'h80008c04,256,0,0,DECERR); // One word beyond a 4 KiB boundary.
        // Real status endpoint and protocol models for three control ports.
        read_burst(0,64'h10004008,1,32'h41584931,1,OKAY);
        write_burst(0,64'h10004000,1,1,4'hf,0,OKAY);
        read_burst(0,64'h10004000,1,1,1,OKAY);
        for(int n=1;n<LITE_PORTS;n++) begin
            logic [63:0] a;
            case(n) 1:a=64'h20000000;2:a=64'h20010000;3:a=64'h20020000;
                4:a=64'h10005000;5:a=64'h10006000;default:a=64'h10007000;endcase
            read_burst(0,a,1,32'hface0000+32'(n),1,OKAY);
            write_burst(0,a,1,32'h98760000+32'(n),4'hf,1,OKAY);
            read_burst(0,a,1,32'h98760000+32'(n),1,OKAY);
        end
        read_burst(0,64'h180000000,2,0,0,DECERR);
        write_burst(0,64'h180000000,3,1,4'hf,1,DECERR);
        read_burst(1,64'h20000000,1,0,0,DECERR); // DMA must not control devices.
        read_burst(1,64'h10005000,1,0,0,DECERR);
        write_burst(2,64'h10006010,1,1,4'hf,0,DECERR);
        write_burst(3,64'h10007010,1,1,4'hf,0,DECERR);
        read_burst(0,64'h10005008,1,0,0,DECERR);
        read_burst(0,64'h10006014,1,0,0,DECERR);
        read_burst(0,64'h10007014,1,0,0,DECERR);
        write_burst(2,64'h10003000,1,1,4'hf,0,DECERR);
        read_burst(0,64'h80000ffc,2,0,0,DECERR); // 4 KiB boundary.
        write_burst(3,64'h80000ffc,2,1,4'hf,0,DECERR);
        read_burst(0,64'h20000080,1,0,0,DECERR); // no control-window aliases.
        // Two continuously active masters exercise transaction RR under stalls.
        fork
            begin for(int n=0;n<8;n++) write_burst(1,64'h80004000+64'(n*64),8,32'(n*100),4'hf,1,OKAY);end
            begin for(int n=0;n<8;n++) write_burst(2,64'h80005000+64'(n*64),8,32'(n*200),4'hf,0,OKAY);end
            begin for(int n=0;n<8;n++) read_burst(3,64'h80001000,1,32'h12ab00cd,1,OKAY);end
        join
        @(negedge clk);lock_request=1;wait(lock_grant);
        fork
            begin write_burst(1,64'h80006000,1,99,4'hf,1,OKAY);end
            begin
                write_burst(0,64'h80006000,1,11,4'hf,0,OKAY);
                read_burst(0,64'h80006000,1,11,1,OKAY);
                repeat(10) @(negedge clk);lock_request=0;
            end
        join
        read_burst(0,64'h80006000,1,99,1,OKAY);
        assert(snoops==141) else $fatal(1,"Snoop count %0d",snoops); // 12 + 128 + 1
        $display("PASS AXI_FABRIC checks=%0d snoops=%0d cycles=%0d",checks,snoops,cycles);$finish;
    end
endmodule
