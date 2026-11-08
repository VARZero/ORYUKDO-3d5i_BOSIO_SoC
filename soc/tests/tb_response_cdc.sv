`timescale 1ns/1ps
module tb_response_cdc;
    logic s_clk=0,d_clk=0,reset_n=0;
    integer sp=5,dp=13;
    bit s_run=1,d_run=1;
    always begin #(sp); if(s_run) s_clk=~s_clk; end
    initial begin #0.3; forever begin #(dp); if(d_run) d_clk=~d_clk; end end
    wire sr,dr;
    or_bo_reset_sync sreset(.clk(s_clk),.reset_n,.local_reset_n(sr));
    or_bo_reset_sync dreset(.clk(d_clk),.reset_n,.local_reset_n(dr));
    logic [3:0] s_data=0;
    logic s_valid=0,d_ready=0;
    wire s_ready,d_valid;
    wire [3:0] d_data;
    or_bo_cdc_mailbox #(.WIDTH(4),.SYNC_PAYLOAD(1)) dut(
        .s_clk,.s_reset_n(sr),.d_clk,.d_reset_n(dr),.s_data,.s_valid,.s_ready,.d_data,.d_valid,.d_ready);
    logic [3:0] expected[$];
    int sent=0,received=0,aborted=0,stalls=0;
    int seed=1;
    logic [31:0] random_s=32'h1337,random_d=32'h9876;
    bit producing=0,consuming=1;
    logic [15:0] values_seen=0;
    logic held=0;logic [3:0] held_data;
    function automatic logic [31:0] step(input logic [31:0] x);
        return {x[30:0],x[31]^x[21]^x[1]^x[0]};
    endfunction
    always @(negedge s_clk) begin
        random_s=step(random_s);
        if(!sr) s_valid=0;
        else if(!s_valid || s_ready) begin
            s_valid=producing && random_s[2:0]!=0;
            s_data=random_s[19:16];
        end
    end
    always @(negedge d_clk) begin
        random_d=step(random_d);
        d_ready=dr && consuming && random_d[3:0]>3;
    end
    always @(posedge s_clk) if(sr && s_valid && s_ready) begin
        expected.push_back(s_data);sent++;
    end
    always @(posedge d_clk) begin
        if(!dr) held<=0;
        else begin
            if(held && (!d_valid || d_data!==held_data)) $fatal(1,"B payload changed while stalled");
            held<=d_valid&&!d_ready;held_data<=d_data;
            if(d_valid && !d_ready) stalls++;
            if(d_valid && d_ready) begin
                if(expected.size()==0) $fatal(1,"Duplicate or phantom B response");
                if(d_data!==expected.pop_front()) $fatal(1,"B response reordered/corrupted");
                values_seen[d_data]=1;received++;
            end
        end
    end
    task automatic drain;
        #0.1;producing=0;consuming=1;
        repeat(40) @(negedge s_clk);
        wait(expected.size()==0 && s_ready && !d_valid);
    endtask
    task automatic reset_both;
        reset_n=0;producing=0;
        #1;aborted+=expected.size();expected.delete();
        #80;reset_n=1;
        wait(sr && dr);
        repeat(10) @(negedge d_clk);
        #0.1;
        if(d_valid || !s_ready) $fatal(1,"Mailbox not empty after shared reset");
    endtask
    initial begin
        if($value$plusargs("seed=%d",seed)) begin random_s^=32'(seed);random_d^=32'(seed*7);end
        reset_both();
        // Fast source / slow destination, then the reverse, both with stalls.
        producing=1;repeat(10000) @(negedge s_clk);drain();
        sp=19;dp=3;
        producing=1;repeat(10000) @(negedge s_clk);drain();
        // Stop the receiver clock with a response outstanding; source must wait.
        @(negedge d_clk);#0.1;d_run=0;producing=1;
        wait(expected.size()!=0);repeat(20) @(negedge s_clk);
        if(s_ready || expected.size()!=1) $fatal(1,"Source overwrote pending response");
        d_run=1;drain();
        // Reset an in-flight transfer, then prove no stale/phantom response leaks.
        consuming=0;producing=1;wait(d_valid);repeat(8) @(negedge d_clk);
        reset_both();consuming=1;producing=1;
        repeat(5000) @(negedge s_clk);drain();
        if(values_seen!==16'hffff || stalls==0 || aborted==0 || sent!=received+aborted)
            $fatal(1,"CDC coverage/counts incomplete");
        $display("PASS RESPONSE_CDC seed=%0d sent=%0d received=%0d aborted=%0d stalls=%0d values=%h",seed,sent,received,aborted,stalls,values_seen);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Response CDC timeout");end
endmodule
