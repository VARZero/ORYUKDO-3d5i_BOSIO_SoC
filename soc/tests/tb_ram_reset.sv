`timescale 1ns/1ps
module tb_ram_reset;
    bit clk=0,rst_n=0;
    always #5 clk=~clk;
    logic request=0,manual_mode=1,manual_write=0;
    logic [31:0] address=32'h80000000;
    wire request_ready,response_valid,response_error,idle;
    wire [31:0] response_data,araddr,hits,misses,stalls;
    wire [2:0] response_user,arsize;
    wire [7:0] arlen;
    wire arvalid,rready;
    logic bus_active=0;
    int beat=0,cycle=0,generation=1,checks=0;
    wire rvalid=bus_active && cycle%3!=0;
    wire [31:0] rdata=32'ha5000000 | (32'(generation)<<12) | 32'(beat);
    wire rlast=beat==3;
    wire full,empty;
    wire [5:0] fifo_count;
    wire [23:0] fifo_data;
    wire output_ready=fifo_count<8;
    bosio_out_fifo #(.ADDR_WIDTH(5)) fifo(
        .clk,.rst_n,.flush(1'b0),.wr_en(manual_mode?manual_write:response_valid&&output_ready),
        .din(manual_mode?24'hc0ffee:response_data[23:0]),.full,.count(fifo_count),
        .rd_en(1'b0),.dout(fifo_data),.empty);
    varzero_cache_line #(.LINE_BYTES(16),.CACHE_BYTES(128),.WAYS(2)) cache(
        .clk,.rst_n,.invalidate(1'b0),.req_valid(request),.req_ready(request_ready),
        .req_addr(address),.req_user(3'b101),.rsp_valid(response_valid),.rsp_ready(output_ready),
        .rsp_data(response_data),.rsp_user(response_user),.rsp_error(response_error),
        .prefetch_valid(1'b0),.prefetch_ready(),.prefetch_addr(32'b0),.idle,
        .hits,.misses,.stall_cycles(stalls),.araddr,.arlen,.arsize,.arvalid,
        .arready(!bus_active),.rdata,.rresp(2'b00),.rlast,.rvalid,.rready);
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(!rst_n) begin bus_active<=0;beat<=0;end
        else begin
            if(arvalid&&!bus_active)begin
                assert(arlen==3&&arsize==2)else $fatal(1,"Bad cache burst");
                bus_active<=1;beat<=0;
            end
            if(rvalid&&rready)begin
                if(beat==3)bus_active<=0;else beat<=beat+1;
            end
        end
        if(cycle>50000)$fatal(1,"RAM reset timeout");
    end
    task automatic issue(input logic [31:0] a);
        @(negedge clk);address=a;request=1;
        do @(posedge clk);while(!request_ready);
        @(negedge clk);request=0;
    endtask
    task automatic reset_off_edge;
        logic [31:0] read_index;
        logic [5:0] count_before;
        logic read_enable;
        logic [23:0] saved_word;
        @(negedge clk);#1;
        saved_word=fifo.mem[0];
        read_index=cache.read_index;read_enable=cache.read_en;count_before=fifo_count;
        rst_n=0;#2;
        // The original asynchronous fifo_cnt reset changes this cache address
        // cone between edges when a replay is blocked by output backpressure.
        assert(fifo_count===count_before&&cache.read_index===read_index&&cache.read_en===read_enable)
            else $fatal(1,"RAM address/enable changed asynchronously on reset");
        repeat(5)@(negedge clk);
        assert(empty&&fifo_count==0&&!response_valid&&cache.valid_bits==0)
            else $fatal(1,"Reset left valid FIFO/cache data");
        assert(fifo.mem[0]===saved_word)else $fatal(1,"Reset corrupted unrelated FIFO location");
        manual_write=0;manual_mode=0;generation++;rst_n=1;
        repeat(4)@(negedge clk);checks++;
    endtask
    initial begin
        repeat(6)@(negedge clk);rst_n=1;
        repeat(3)@(negedge clk);manual_write=1;
        repeat(7)@(negedge clk);manual_write=0;
        issue(32'h80000020);
        // Occupy the last slot while the miss is filling, then make the live
        // request address different from the held replay address.
        manual_write=1;@(negedge clk);manual_write=0;address=32'h80000040;
        while(cache.state!=3)@(negedge clk);
        assert(fifo_count==8&&!output_ready)else $fatal(1,"Replay-stall scenario not reached");
        reset_off_edge();
        issue(32'h80000020);
        while(!response_valid)@(negedge clk);
        assert(response_data==(32'ha5000000 | (32'(generation)<<12))&&!response_error&&response_user==5&&misses==1)
            else $fatal(1,"Stale cache data survived reset");
        checks++;
        // Reset during an active refill. No partial line may remain valid.
        while(!idle)@(negedge clk);
        issue(32'h80000060);
        while(!(bus_active&&beat==1))@(negedge clk);
        manual_mode=1;manual_write=1;reset_off_edge();
        issue(32'h80000060);
        while(!response_valid)@(negedge clk);
        assert(response_data==(32'ha5000000 | (32'(generation)<<12))&&!response_error&&misses==1)
            else $fatal(1,"Partial fill survived reset");
        checks++;
        $display("PASS RAM_RESET checks=%0d cycles=%0d",checks,cycle);$finish;
    end
endmodule
