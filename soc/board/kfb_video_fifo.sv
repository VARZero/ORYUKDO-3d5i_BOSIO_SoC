// Board-only deeper instance of the verified XPM transport. Existing CPU
// and snoop wrappers are unchanged. Read credits account for in-flight DDR.
// AMD asynchronous FIFO transport. AXI uses capacity-based ready; snoop waits
// for actual destination consumption before returning ready.
// In particular, snoop_ready must not return until the CPU consumes invalidation.
// Common reset revokes this channel. Local endpoint resets only gate traffic;
// both owners must join common reset. This cannot undo an issued DDR write.
module kfb_video_fifo #(parameter int WIDTH=256, parameter int DEPTH=512, parameter bit WAIT_CONSUMED=0)( 
    input wire reset_n,s_clk,s_reset_n,d_clk,d_reset_n,
    input wire [WIDTH-1:0] s_data,input wire s_valid,output wire s_ready,
    output wire [$clog2(DEPTH):0] used, output wire online,
    output wire [WIDTH-1:0] d_data,output wire d_valid,input wire d_ready
);
    wire source_reset_n,dest_reset_n;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) source_reset(
        .src_arst(reset_n),.dest_clk(s_clk),.dest_arst(source_reset_n));
    xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) dest_reset(
        .src_arst(reset_n),.dest_clk(d_clk),.dest_arst(dest_reset_n));

    // XPM FIFO rst is synchronous to wr_clk. Asynchronous assertion above also
    // remembers reset while a clock is paused; no traffic resumes during flush.
    logic fifo_reset=1'b1;
    always_ff @(posedge s_clk) fifo_reset<=!source_reset_n;
    wire wr_busy,rd_busy,full,empty;
    wire [WIDTH-1:0] fifo_data;
    // Three small output slots absorb the registered RAM read without routing
    // asynchronous cancellation or downstream READY onto BRAM read enable.
    logic [WIDTH-1:0] output_words[3];
    logic [1:0] output_count,read_index,write_index;
    logic read_pending;
    wire output_valid=output_count!=0;
    always_ff @(posedge d_clk) if(read_pending) output_words[write_index]<=fifo_data;
    // Synchronous controls keep asynchronous reset assertion off BRAM pins.
    logic source_run=0,dest_run=0;
    always_ff @(posedge s_clk) source_run<=source_reset_n && s_reset_n;
    always_ff @(posedge d_clk) dest_run<=dest_reset_n && d_reset_n;
    typedef enum logic [1:0] {WAIT_BUSY,WAIT_DONE,ONLINE} reset_state_t;
    reset_state_t source_state,dest_state;
    logic request,consumed;
    wire consumed_sync;
    wire source_offer=source_run && source_state==ONLINE && !fifo_reset &&
                      !wr_busy && !full && (!WAIT_CONSUMED || request==consumed_sync);
    wire dest_offer=dest_run && dest_state==ONLINE && !rd_busy && output_valid;
    // External interfaces cancel asynchronously. Internal RAM strobes remain
    // synchronous; the common FIFO reset flushes any already pending transfer.
    wire push=s_valid && source_offer;
    wire pop=dest_offer && d_ready;
    wire fetch=dest_run && dest_state==ONLINE &&
               !rd_busy && !empty && (int'(output_count)+int'(read_pending)<3);

    always_ff @(posedge s_clk)
        if(!source_reset_n) begin source_state<=WAIT_BUSY;request<=0;end
        else begin
            case(source_state)
                WAIT_BUSY:if(wr_busy) source_state<=WAIT_DONE;
                WAIT_DONE:if(!fifo_reset && !wr_busy) source_state<=ONLINE;
                ONLINE:begin end
                default:source_state<=WAIT_BUSY;
            endcase
            if(push) request<=!request;
        end
    always_ff @(posedge d_clk)
        if(!dest_reset_n) begin
            dest_state<=WAIT_BUSY;consumed<=0;output_count<=0;read_index<=0;write_index<=0;read_pending<=0;
        end
        else begin
            case(dest_state)
                WAIT_BUSY:if(rd_busy) dest_state<=WAIT_DONE;
                WAIT_DONE:if(!rd_busy) dest_state<=ONLINE;
                ONLINE:begin end
                default:dest_state<=WAIT_BUSY;
            endcase
            read_pending<=fetch;
            if(read_pending) write_index<=write_index==2?0:write_index+1'b1;
            if(pop) read_index<=read_index==2?0:read_index+1'b1;
            case({read_pending,pop})
                2'b10:output_count<=output_count+1'b1;
                2'b01:output_count<=output_count-1'b1;
                default:begin end
            endcase
            if(pop) consumed<=!consumed;
        end
    if(WAIT_CONSUMED) begin: completion_path
    xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) completion_sync(
        .src_clk(d_clk),.src_in(consumed),.dest_clk(s_clk),.dest_out(consumed_sync));
    end else assign consumed_sync=1'b0;
    assign online=source_reset_n && s_reset_n && source_run && source_state==ONLINE && !fifo_reset && !wr_busy;
    assign s_ready=source_reset_n && s_reset_n && source_offer;
    assign d_valid=dest_reset_n && d_reset_n && dest_offer;
    assign d_data=output_words[read_index];
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(DEPTH),.WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),
        .READ_MODE("std"),.FIFO_READ_LATENCY(1),.CDC_SYNC_STAGES(3),
        .WR_DATA_COUNT_WIDTH($clog2(DEPTH)+1),.RD_DATA_COUNT_WIDTH($clog2(DEPTH)+1),.USE_ADV_FEATURES("0404"),
        // 2022.2's EMPTY_CHECK demands $rose(empty) even when already empty;
        // SLEEP_CHECK also fires at startup for constant sleep=0, WAKEUP_TIME=0.
        // Use the explicit interface/reset assertions below and the scoreboard.
        // Production synthesis still uses the unmodified installed AMD macro.
        .PROG_FULL_THRESH(8),.PROG_EMPTY_THRESH(8),.SIM_ASSERT_CHK(0)
    ) transport(
        .sleep(1'b0),.rst(fifo_reset),.wr_clk(s_clk),.wr_en(push),.din(s_data),
        .full,.wr_rst_busy(wr_busy),.rd_clk(d_clk),.rd_en(fetch),.dout(fifo_data),
        .empty,.rd_rst_busy(rd_busy),.injectsbiterr(1'b0),.injectdbiterr(1'b0),
        .prog_full(),.wr_data_count(used),.overflow(),.almost_full(),.wr_ack(),
        .prog_empty(),.rd_data_count(),.underflow(),.almost_empty(),.data_valid(),
        .sbiterr(),.dbiterr());
`ifndef SYNTHESIS
    always @(posedge s_clk) if(source_reset_n && push)
        assert(!wr_busy && !fifo_reset && !full) else $fatal(1,"XPM write during reset/full");
    always @(posedge d_clk) if(reset_n && dest_reset_n) assert(output_count<=3) else $fatal(1,"CDC output buffer overflow");
    always @(posedge d_clk) if(dest_reset_n && fetch)
        assert(!rd_busy && !empty) else $fatal(1,"XPM read during reset/empty");
    always @(posedge d_clk) if(dest_reset_n && dest_state==WAIT_DONE && !rd_busy)
        assert(empty && !output_valid && !read_pending)
            else $fatal(1,"XPM reset completed with stale data");
`endif
endmodule
