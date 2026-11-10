`timescale 1ns/1ps
// Branch resolution FIFO: in-order checkpoint reclamation even if EX outcomes
// arrive out of order. One branch admit per cycle (the current Gen2 NEL model).
// The checker stops new allocations on a full queue. The caller must hold
// i_push until o_push_ready, and stall NEL when full.
// On misprediction it raises o_recovery_valid until i_recovery_done; external
// modules must squash younger instructions and drain all in-flight activity
// before acknowledging. NO physical register is reclaimed here.
module oryukdo_branch_recovery #(
    parameter int PC_W=32, FLOW_WINDOWS=8,
    parameter int FLOW_W=(FLOW_WINDOWS>1?$clog2(FLOW_WINDOWS):1),
    parameter int SLOT_W=4, PHY_W=6, LOGICAL_REGS=32,
    parameter int DEPTH=32, PER_WINDOW=4, RESOLVE_LANES=1,
    localparam int TAG_W=FLOW_W+SLOT_W,
    localparam int MAP_W=PHY_W*LOGICAL_REGS,
    localparam int PTR_W=DEPTH>1?$clog2(DEPTH):1,
    localparam int COUNT_W=$clog2(DEPTH+1)
)(
    input wire clk, reset_n,
    input wire i_push,
    output wire o_push_ready,
    input wire [TAG_W-1:0] i_push_tag,
    input wire [PC_W-1:0] i_push_predicted_next_pc,
    input wire [MAP_W-1:0] i_push_rename_map,
    input wire [RESOLVE_LANES-1:0] i_resolve_valid,
    input wire [RESOLVE_LANES*TAG_W-1:0] i_resolve_tag,
    input wire [RESOLVE_LANES*PC_W-1:0] i_resolve_next_pc,
    output logic o_recovery_valid,
    output logic [TAG_W-1:0] o_recovery_tag,
    output logic [PC_W-1:0] o_redirect_pc,
    output logic [MAP_W-1:0] o_restore_map,
    input wire i_recovery_done, i_trap_flush,
    output wire [TAG_W-1:0] o_head_tag,
    output wire [COUNT_W-1:0] o_outstanding
);
    logic [TAG_W-1:0] tag_q[DEPTH];
    logic [PC_W-1:0] prediction_q[DEPTH], actual_q[DEPTH];
    logic [MAP_W-1:0] map_q[DEPTH];
    logic [DEPTH-1:0] valid_q, resolved_q;
    logic [PTR_W-1:0] head, tail;
    logic [COUNT_W-1:0] count;
    localparam int USED_W=$clog2(PER_WINDOW+1);
    wire [USED_W-1:0] usage[FLOW_WINDOWS];
    wire [USED_W-1:0] window_used=usage[i_push_tag[TAG_W-1:SLOT_W]];
    wire head_resolved = (count != 0) && resolved_q[head];
    wire head_wrong = head_resolved && (prediction_q[head] != actual_q[head]);
    wire take_head = head_resolved && !o_recovery_valid && !head_wrong;
    wire trigger = head_wrong && !o_recovery_valid;
    wire flush = o_recovery_valid && i_recovery_done;
    assign o_push_ready = (int'(count) < DEPTH) && (int'(window_used) < PER_WINDOW) && !o_recovery_valid && !trigger;
    assign o_outstanding = count;
    function automatic [PTR_W-1:0] next_ptr(input logic [PTR_W-1:0] ptr);
        return ptr == PTR_W'(DEPTH-1) ? '0 : ptr+1'b1;
    endfunction
    logic [TAG_W-1:0] head_tag;
    assign o_head_tag=head_tag;
    always_ff @(posedge clk) begin
        if (take_head && count>1) head_tag<=tag_q[next_ptr(head)];
        else if (i_push && o_push_ready && (count==0 || (take_head && count==1))) head_tag<=i_push_tag;
    end
    for(genvar w=0;w<FLOW_WINDOWS;w++) begin : G_USAGE
        logic [USED_W-1:0] used;
        wire push_window=i_push && o_push_ready && i_push_tag[TAG_W-1:SLOT_W]==FLOW_W'(w);
        wire pop_window=take_head && tag_q[head][TAG_W-1:SLOT_W]==FLOW_W'(w);
        assign usage[w]=used;
        // synthesis translate_off
        always @(posedge clk) if(reset_n) assert(int'(used)<=PER_WINDOW)
            else $fatal(1,"Per-window branch checkpoint overflow");
        // synthesis translate_on
        always_ff @(posedge clk) begin
            if(!reset_n) used<='0;
            else if(flush || i_trap_flush) used<='0;
            else case({push_window,pop_window})
                2'b10: used<=used+1'b1;
                2'b01: used<=used-1'b1;
                default: ;
            endcase
        end
    end
    // Single-write snapshot and prediction memories. Valid bits own their lifetime.
    always_ff @(posedge clk) if(i_push && o_push_ready) begin
        map_q[tail]<=i_push_rename_map;
        prediction_q[tail]<=i_push_predicted_next_pc;
    end
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            head <= '0; tail <= '0; count <= '0;
            valid_q <= '0; resolved_q <= '0;
            o_recovery_valid <= 1'b0; o_recovery_tag <= '0;
            o_redirect_pc <= '0; o_restore_map <= '0;
        end else if (flush || i_trap_flush) begin
            // Conservative initial protocol: all younger checkpoints are dropped.
            // Old/valid predecessors have been acknowledged in FIFO order.
            head <= '0; tail <= '0; count <= '0;
            valid_q <= '0; resolved_q <= '0;
            o_recovery_valid <= 1'b0;
        end else begin
            if (trigger) begin
                o_recovery_valid <= 1'b1;
                o_recovery_tag <= tag_q[head];
                o_redirect_pc <= actual_q[head];
                o_restore_map <= map_q[head];
            end
            if (take_head) begin
                valid_q[head] <= 1'b0;
                resolved_q[head] <= 1'b0;
                head <= next_ptr(head);
            end
            if (i_push && o_push_ready) begin
                tag_q[tail] <= i_push_tag;
                valid_q[tail] <= 1'b1;
                resolved_q[tail] <= 1'b0;
                tail <= next_ptr(tail);
            end
            case ({(i_push && o_push_ready),take_head})
                2'b10: count <= count+1'b1;
                2'b01: count <= count-1'b1;
                default: ;
            endcase
            // Results may arrive out-of-order. A result for a newly inserted
            // entry cannot be accepted in the same cycle as insertion.
            // Priority: each entry gets at most one update in a cycle.
            for (int n=0; n<DEPTH; n++) begin
                if (valid_q[n] && !(take_head && head == PTR_W'(n))) begin
                    for (int lane=0; lane<RESOLVE_LANES; lane++) begin
                        if (i_resolve_valid[lane] &&
                            tag_q[n] == i_resolve_tag[lane*TAG_W +: TAG_W] &&
                            !resolved_q[n]) begin
                            actual_q[n] <= i_resolve_next_pc[lane*PC_W +: PC_W];
                            resolved_q[n] <= 1'b1;
                        end
                    end
                end
            end
        end
    end
    // This controller intentionally does not decide whether EX/store/CSR
    // are drained: the top-level caller owns the i_recovery_done contract.
    // synthesis translate_off
    always @(posedge clk) if (reset_n) begin
        assert(int'(count) <= DEPTH);
        assert(!i_push || o_push_ready) else $error("NEL ignored branch checkpoint backpressure");
    end
    // synthesis translate_on
endmodule
