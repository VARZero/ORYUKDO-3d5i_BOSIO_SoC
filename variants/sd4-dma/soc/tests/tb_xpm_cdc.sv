`timescale 1ns/1ps
module bundled_checker #(parameter int WIDTH=99, ID=0, SOC_RESET=0, QUEUED=0)(output bit done=0);
    localparam bit WAIT_CONSUMED=!QUEUED || ID==4;
    logic s_clk=0,d_clk=0,reset_n=0;
    int sp=10,dp=5;
    bit s_run=1,d_run=1;
    always begin #(sp); if(s_run) s_clk=~s_clk; end
    initial begin #(0.123+ID*0.031); forever begin #(dp); if(d_run) d_clk=~d_clk; end end
    wire sr,dr;
    if(SOC_RESET && ID<3) begin
        reviewed_cpu_reset sreset(.clk(s_clk),.reset_n,.local_reset_n(sr));
    end else or_bo_reset_sync sreset(.clk(s_clk),.reset_n,.local_reset_n(sr));
    if(SOC_RESET && ID>=3) begin
        reviewed_cpu_reset dreset(.clk(d_clk),.reset_n,.local_reset_n(dr));
    end else or_bo_reset_sync dreset(.clk(d_clk),.reset_n,.local_reset_n(dr));
    logic [WIDTH-1:0] s_data=0;
    logic s_valid=0,d_ready=0;
    wire s_ready,d_valid;
    wire [WIDTH-1:0] d_data;
    or_bo_xpm_mailbox #(.WIDTH(WIDTH),.WAIT_CONSUMED(WAIT_CONSUMED)) dut(
        .reset_n,.s_clk,.s_reset_n(sr),.d_clk,.d_reset_n(dr),.s_data,.s_valid,.s_ready,.d_data,.d_valid,.d_ready);
    logic [WIDTH-1:0] expected[$];
    int sent=0,received=0,aborted=0,stalls=0,seed=1,phase=0;
    logic [31:0] random_s=32'h1337,random_d=32'h9876;
    bit producing=0,consuming=1;
    logic [WIDTH-1:0] seen_one=0,seen_zero=0;
    logic held=0; logic [WIDTH-1:0] held_data;
    function automatic logic [31:0] step(input logic [31:0] x);
        return {x[30:0],x[31]^x[21]^x[1]^x[0]};
    endfunction
    always @(negedge s_clk) begin
        random_s=step(random_s);
        if(!reset_n || !sr) s_valid=0;
        else if(!s_valid || s_ready) begin
            s_valid=producing && random_s[2:0]!=0;
            for(int i=0;i<WIDTH;i++) begin
                random_s=step(random_s);s_data[i]=random_s[31];
            end
            // Structured patterns exercise coherence at all bit positions too.
            case(sent%8)
                0:s_data='0;
                1:s_data='1;
                2:begin s_data='0;s_data[(sent/8)%WIDTH]=1;end
                3:begin s_data='1;s_data[(sent/8)%WIDTH]=0;end
                default:begin end
            endcase
        end
    end
    always @(negedge d_clk) begin
        random_d=step(random_d);
        d_ready=dr && consuming && random_d[3:0]>3;
    end
    always @(posedge s_clk) if(reset_n && sr && s_valid && s_ready) begin
        expected.push_back(s_data);sent++;
        if(expected.size()>(WAIT_CONSUMED?1:19)) $fatal(1,"id=%0d pending transaction overwritten",ID);
    end
    always @(posedge d_clk) begin
        if(!reset_n || !dr) held<=0;
        else begin
            if(held && (!d_valid || d_data!==held_data)) begin
                $display("HOLD_DIAG id=%0d phase=%0d raw=%b sr=%b dr=%b srst=%b drst=%b run=%b/%b state=%d/%d busy=%b/%b empty=%b fetch=%b valid=%b ready=%b old=%h new=%h",ID,phase,reset_n,sr,dr,dut.source_reset_n,dut.dest_reset_n,dut.source_run,dut.dest_run,dut.source_state,dut.dest_state,dut.wr_busy,dut.rd_busy,dut.empty,dut.fetch,d_valid,d_ready,held_data,d_data);
                $fatal(1,"id=%0d output changed while stalled",ID);
            end
            held<=d_valid&&!d_ready;held_data<=d_data;
            if(d_valid && !d_ready) stalls++;
            if(d_valid && d_ready) begin
                if(expected.size()==0) $fatal(1,"id=%0d duplicate/phantom transaction",ID);
                if(d_data!==expected.pop_front()) $fatal(1,"id=%0d reordered/corrupted data",ID);
                seen_one|=d_data;seen_zero|=~d_data;received++;
            end
        end
    end
    task automatic drain;
        #0.1;producing=0;consuming=1;
        repeat(40) @(negedge s_clk);
        // Sample after clock activity: do not depend on simulator sensitivity
        // inference for a dynamic-queue method inside a wait expression.
        #0.001;
        while(expected.size()!=0 || !s_ready || d_valid) begin
            @(negedge s_clk);#0.001;
        end
        #0.1;
    endtask
    task automatic reset_both;
        #0.1;reset_n=0;producing=0;
        #1;aborted+=expected.size();expected.delete();
        // Keep both clocks running during reset; settle both reset chains.
        #1200;reset_n=1;
        wait(sr && dr && s_ready);
        repeat(10) @(negedge d_clk);
        #0.1;
        if(d_valid || !s_ready) $fatal(1,"id=%0d not empty after common reset",ID);
    endtask
    task automatic reset_paused(input bit pause_source);
        drain();consuming=0;producing=1;wait(d_valid);
        if(pause_source) begin @(negedge s_clk);#0.1;s_run=0;end
        else begin @(negedge d_clk);#0.1;d_run=0;end
        reset_n=0;producing=0;
        #1;aborted+=expected.size();expected.delete();
        #1200;reset_n=1;
        #1200;
        // BRAM-facing controls reset synchronously. A stopped domain cannot
        // transfer; its old pin values may persist until its clock resumes.
        // The running domain must already be quiescent.
        if((!pause_source && s_ready) || (pause_source && d_valid))
            $fatal(1,"id=%0d running side resumed before reset handshake",ID);
        s_run=1;d_run=1;
        wait(sr && dr && s_ready);
        repeat(10) @(negedge d_clk);#0.1;
        if(d_valid || expected.size()!=0) $fatal(1,"id=%0d stale data after paused reset",ID);
        consuming=1;producing=1;repeat(1000) @(negedge s_clk);drain();
    endtask
    initial begin
        if($value$plusargs("seed=%d",seed)) begin random_s^=32'(seed+ID*97);random_d^=32'(seed*7+ID);end
        reset_both();
        // Actual 50 -> 100 MHz ratio, inverse ratio, and much larger skew.
        phase=1;producing=1;repeat(12000) @(negedge s_clk);drain();
        phase=2;sp=5;dp=10;producing=1;repeat(12000) @(negedge s_clk);drain();
        phase=3;sp=19;dp=3;producing=1;repeat(12000) @(negedge s_clk);drain();
        phase=4;sp=3;dp=23;producing=1;repeat(12000) @(negedge s_clk);drain();
        // Receiver clock stops before notification can cross.
        phase=5;@(negedge d_clk);#0.1;d_run=0;producing=1;
        while(expected.size()==0) begin @(negedge s_clk);#0.001;end
        repeat(80) @(negedge s_clk);#0.1;
        if(s_ready || (WAIT_CONSUMED?expected.size()!=1:(expected.size()<2 || expected.size()>19))) $fatal(1,"id=%0d overwrote pending word",ID);
        d_run=1;drain();
        // Source clock stops with a request pending; destination must consume once.
        phase=6;consuming=0;producing=1;wait(d_valid);
        @(negedge s_clk);#0.1;s_run=0;producing=0;consuming=1;
        repeat(80) @(negedge d_clk);#0.1;
        if(expected.size()!=0 || d_valid) $fatal(1,"id=%0d failed source-clock pause",ID);
        s_run=1;drain();
        // Reset at varying points before capture, while stalled, and after consume.
        for(int n=0;n<18;n++) begin
            phase=10+n;
            consuming=0;producing=1;
            while(expected.size()==0) begin @(negedge s_clk);#0.001;end
            if(n%3==0) begin #0.2; end
            else begin
                wait(d_valid);
                if(n%3==1) repeat(8) @(negedge d_clk);
                else begin
                    #0.1;producing=0;consuming=1;
                    while(expected.size()!=0) begin @(negedge d_clk);#0.001;end
                end
            end
            reset_both();
            consuming=1;producing=1;repeat(500) @(negedge s_clk);drain();
        end
        phase=30;reset_paused(1);
        phase=31;reset_paused(0);
        if(seen_one!=='1 || seen_zero!=='1 || stalls==0 || aborted==0 || sent!=received+aborted)
            $fatal(1,"id=%0d coverage/counts incomplete",ID);
        $display("PASS XPM_CDC id=%0d width=%0d seed=%0d sent=%0d received=%0d aborted=%0d stalls=%0d",ID,WIDTH,seed,sent,received,aborted,stalls);
        done=1;
    end
    initial begin #1500000;if(!done) $display("DIAG id=%0d phase=%0d queued=%0d sent=%0d received=%0d req=%b ack=%b sr=%b dr=%b sready=%b dvalid=%b srun=%b drun=%b producing=%b consuming=%b",ID,phase,expected.size(),sent,received,dut.request,dut.consumed,sr,dr,s_ready,d_valid,s_run,d_run,producing,consuming);end
endmodule

module tb_bundled_cdc #(parameter int SOC_RESET=0, QUEUED=0);
    import or_bo_axi_pkg::*;
    wire [4:0] done;
    bundled_checker #($bits(ax_addr_t),0,SOC_RESET,QUEUED) ar(done[0]);
    bundled_checker #($bits(ax_addr_t),1,SOC_RESET,QUEUED) aw(done[1]);
    bundled_checker #($bits(ax_w_t),2,SOC_RESET,QUEUED) w(done[2]);
    bundled_checker #($bits(ax_r_t),3,SOC_RESET,QUEUED) r(done[3]);
    bundled_checker #(32,4,SOC_RESET,QUEUED) snoop(done[4]);
    initial begin wait(&done);$display("PASS ALL_XPM_CDC");$finish;end
    initial begin #8000000;$fatal(1,"Bundled CDC timeout");end
endmodule
module tb_soc_reset_cdc;
    tb_bundled_cdc #(.SOC_RESET(1)) tb();
endmodule

module tb_queued_cdc; tb_bundled_cdc #(.QUEUED(1)) tb(); endmodule
module tb_queued_soc_reset_cdc; tb_bundled_cdc #(.QUEUED(1),.SOC_RESET(1)) tb(); endmodule
