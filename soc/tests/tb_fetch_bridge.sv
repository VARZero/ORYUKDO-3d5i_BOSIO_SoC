`timescale 1ns/1ps
module fetch_bridge_checker #(parameter bit BURST=1)(output bit done=0);
    import or_bo_axi_pkg::*;
    bit clk=0,reset_n=0;
    always #5 clk=~clk;
    logic if_valid=0,if_response_ready=0;
    logic [31:0] if_address=0;
    wire if_ready,if_response_valid;
    wire [95:0] if_data;
    wire [2:0] if_fault;
    ax_req_t req;ax_rsp_t rsp;
    or_bo_cpu_axi #(.FETCH_BURST(BURST)) dut(
        .clk,.reset_n,.if_valid,.if_ready,.if_address,.if_response_valid,
        .if_response_ready,.if_data,.if_fault,
        .data_valid(1'b0),.data_ready(),.data_store(1'b0),.data_address(32'b0),
        .data_write(32'b0),.data_mask(4'b0),.data_response_valid(),
        .data_response_ready(1'b0),.data_read(),.data_fault(),.data_cause(),.req,.rsp);
    bit read_active=0,present=0,pause_r=0;
    logic [31:0] addr;
    int left=0,cycles=0,reads=0,checks=0,seed=1;
    function automatic bit mapped(input logic [31:0] a);
        return (a>=32'h10000&&a<32'h11000)||(a>=32'h20000&&a<32'h60000)||
               (a>=32'h80000000&&a<32'hc0000000);
    endfunction
    function automatic logic [31:0] contents(input logic [31:0] a);
        return (a^32'h65a91c37)+{a[15:0],a[31:16]};
    endfunction
    always_comb begin
        rsp='0;
        rsp.arready=reset_n&&!read_active&&(cycles%3!=seed%3);
        rsp.rvalid=read_active&&present;
        rsp.r.data=contents(addr);
        rsp.r.resp=addr==32'h80001004 ? SLVERR:OKAY;
        rsp.r.last=left==1;
    end
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(!reset_n) begin read_active<=0;present<=0;left<=0;addr<=0;end
        else begin
            if(req.arvalid&&rsp.arready) begin
                assert(req.ar.size==2&&req.ar.burst==1&&req.ar.len<=2&&req.ar.user==15)
                    else $fatal(1,"Invalid fetch AR attributes");
                assert(int'(req.ar.addr[11:0])+4*(int'(req.ar.len)+1)<=4096)
                    else $fatal(1,"Fetch burst crossed 4 KiB boundary");
                for(int i=0;i<=req.ar.len;i++)
                    assert(mapped(req.ar.addr[31:0]+32'(4*i))) else $fatal(1,"Fetch crossed mapped region");
                addr<=req.ar.addr[31:0];left<=int'(req.ar.len)+1;read_active<=1;reads<=reads+1;
            end
            if(read_active&&!present&&!pause_r&&(cycles%4!=seed%4)) present<=1;
            if(rsp.rvalid&&req.rready) begin
                present<=0;addr<=addr+4;left<=left-1;
                if(left==1)read_active<=0;
            end
        end
        if(cycles>200000)$fatal(1,"Fetch bridge timeout");
    end
    task automatic fetch_bundle(input logic [31:0] a);
        logic [95:0] expected_data;
        logic [2:0] expected_fault;
        int before_reads,expected_reads;
        expected_data=0;expected_fault=0;expected_reads=0;before_reads=reads;
        for(int i=0;i<3;i++) begin
            logic [31:0] word_addr,previous_addr;
            word_addr=a+32'(4*i);previous_addr=word_addr-4;
            if(mapped(word_addr)) begin
                expected_data[32*i+:32]=contents(word_addr);
                expected_fault[i]=word_addr==32'h80001004;
                if(!BURST||i==0||!mapped(previous_addr)||word_addr[31:12]!=previous_addr[31:12])expected_reads++;
            end else expected_fault[i]=1;
        end
        @(negedge clk);if_address=a;if_valid=1;
        do @(posedge clk);while(!if_ready);
        @(negedge clk);if_valid=0;
        while(!if_response_valid)@(negedge clk);
        repeat(3) begin
            assert(if_response_valid&&if_data===expected_data&&if_fault===expected_fault)
                else $fatal(1,"Fetch mismatch burst=%0d address=%h data=%h expected=%h fault=%b expected=%b",BURST,a,if_data,expected_data,if_fault,expected_fault);
            @(negedge clk);
        end
        assert(reads-before_reads==expected_reads)else $fatal(1,"Unexpected AR count at %h",a);
        if_response_ready=1;@(negedge clk);if_response_ready=0;checks++;
    endtask
    initial begin
        if($value$plusargs("seed=%d",seed))begin end
        repeat(6)@(negedge clk);reset_n=1;
        fetch_bundle(32'h80000000);
        fetch_bundle(32'h80000ff4);fetch_bundle(32'h80000ff8);fetch_bundle(32'h80000ffc);
        fetch_bundle(32'h00010ff8);fetch_bundle(32'h00010ffc);
        fetch_bundle(32'h0005fff8);fetch_bundle(32'h0005fffc);
        fetch_bundle(32'hbffffff8);fetch_bundle(32'hbffffffc);
        fetch_bundle(32'h0000fffc);fetch_bundle(32'h0001fffc);fetch_bundle(32'h7ffffffc);
        fetch_bundle(32'h80001000);fetch_bundle(32'h80001004);
        fetch_bundle(32'h10005000);fetch_bundle(32'hfffffffc);
        for(int i=0;i<96;i++)fetch_bundle(32'h80002000+32'((i*97+seed*31)%4096)*4);
        // Cancel an accepted burst with no response delivered, then restart.
        @(negedge clk);pause_r=1;if_address=32'h80004000;if_valid=1;
        do @(posedge clk);while(!if_ready);
        @(negedge clk);if_valid=0;
        while(!read_active)@(negedge clk);
        #2;reset_n=0;repeat(6)@(negedge clk);reset_n=1;pause_r=0;
        fetch_bundle(32'h80005000);
        $display("PASS FETCH_BRIDGE burst=%0d seed=%0d checks=%0d reads=%0d cycles=%0d",BURST,seed,checks,reads,cycles);
        done=1;
    end
endmodule
module tb_fetch_bridge;
    wire [1:0] done;
    fetch_bridge_checker #(.BURST(0)) serial_mode(done[0]);
    fetch_bridge_checker #(.BURST(1)) burst_mode(done[1]);
    initial begin wait(&done);$display("PASS ALL_FETCH_BRIDGE");$finish;end
endmodule
