`timescale 1ns/1ps
// Standalone ordered commit/trap controller for the oldest Flow Window.
// This block is a control-plane component, NOT a complete FCL integration.
// Per-slot completion/squash/exception inputs are stable while a window is active.
// External side-effect unit must only raise i_sidefx_done after o_sidefx_request
// for the matching slot; it must preserve architectural ordering and errors.
module oryukdo_commit_trap_controller #(
    parameter int WINDOW_SIZE=16,
    parameter int COMMIT_WIDTH=3,
    parameter int PC_W=32,
    parameter int CAUSE_W=6,
    parameter int SLOT_W=(WINDOW_SIZE>1?$clog2(WINDOW_SIZE):1),
    parameter int COUNT_W=$clog2(WINDOW_SIZE+1)
)(
    input wire clk, reset_n,
    input wire i_window_open,
    input wire i_window_closed,
    input wire [COUNT_W-1:0] i_window_length,
    input wire [WINDOW_SIZE-1:0] i_slot_valid,
    input wire [WINDOW_SIZE-1:0] i_slot_done,
    input wire [WINDOW_SIZE-1:0] i_slot_squashed,
    input wire [WINDOW_SIZE-1:0] i_slot_exception,
    input wire [WINDOW_SIZE-1:0] i_slot_sidefx,
    input wire [WINDOW_SIZE-1:0] i_sidefx_done,
    input wire [WINDOW_SIZE*PC_W-1:0] i_slot_pc,
    input wire [WINDOW_SIZE*CAUSE_W-1:0] i_slot_cause,
    input wire [WINDOW_SIZE*PC_W-1:0] i_slot_tval,
    input wire [PC_W-1:0] i_next_window_pc,
    input wire i_interrupt_pending,
    input wire [CAUSE_W-1:0] i_interrupt_cause,
    input wire i_trap_ack,
    output logic [COUNT_W-1:0] o_commit_cursor,
    output logic [WINDOW_SIZE-1:0] o_commit_fire,
    output logic o_sidefx_request,
    output logic [SLOT_W-1:0] o_sidefx_slot,
    output logic o_window_commit_done,
    output logic o_trap_valid,
    output logic o_trap_interrupt,
    output logic [PC_W-1:0] o_trap_epc,
    output logic [CAUSE_W-1:0] o_trap_cause,
    output logic [PC_W-1:0] o_trap_tval,
    output logic [SLOT_W-1:0] o_trap_slot
);
    logic [COUNT_W-1:0] cursor;
    logic window_active, window_released;
    logic trap_pending;
    logic trap_interrupt;
    logic [PC_W-1:0] trap_epc, trap_tval;
    logic [CAUSE_W-1:0] trap_cause;
    logic [SLOT_W-1:0] trap_slot;
    logic exception_fire, irq_fire, stop_scan;
    logic [COUNT_W-1:0] cursor_after;
    logic [SLOT_W-1:0] exception_slot;
    wire [COUNT_W:0] scan_index[COMMIT_WIDTH];
    for(genvar n=0;n<COMMIT_WIDTH;n++) assign scan_index[n]=(COUNT_W+1)'(cursor)+(COUNT_W+1)'(n);
    always_comb begin
        o_commit_cursor = cursor;
        o_commit_fire = '0;
        o_sidefx_request = 1'b0;
        o_sidefx_slot = '0;
        cursor_after = cursor;
        exception_fire = 1'b0;
        stop_scan = 1'b0;
        exception_slot = '0;
        irq_fire = 1'b0;
        o_window_commit_done = 1'b0;
        // Prefix scan limited to COMMIT_WIDTH; it never skips a blocked slot.
        if (reset_n && window_active && !window_released && !trap_pending && !i_window_open) begin
            for (int lane=0; lane<COMMIT_WIDTH; lane++) begin
                if (!stop_scan && !exception_fire && int'(scan_index[lane]) < int'(i_window_length)) begin
                    if (i_slot_valid[int'(scan_index[lane])] && i_slot_exception[int'(scan_index[lane])] &&
                        !i_slot_squashed[int'(scan_index[lane])]) begin
                        exception_fire = 1'b1;
                        stop_scan = 1'b1;
                        exception_slot = SLOT_W'(int'(scan_index[lane]));
                    end else if (i_slot_valid[int'(scan_index[lane])] && i_slot_sidefx[int'(scan_index[lane])] &&
                                 !i_slot_squashed[int'(scan_index[lane])] && !i_sidefx_done[int'(scan_index[lane])]) begin
                        o_sidefx_request = 1'b1;
                        o_sidefx_slot = SLOT_W'(int'(scan_index[lane]));
                        stop_scan = 1'b1;
                    end else if (i_slot_valid[int'(scan_index[lane])] &&
                                 (i_slot_done[int'(scan_index[lane])] || i_slot_squashed[int'(scan_index[lane])])) begin
                        if (i_slot_squashed[int'(scan_index[lane])]) begin
                            // Squashed slots are accounted but never committed.
                            cursor_after = COUNT_W'(int'(scan_index[lane])+1);
                        end else begin
                            o_commit_fire[int'(scan_index[lane])] = 1'b1;
                            cursor_after = COUNT_W'(int'(scan_index[lane])+1);
                        end
                    end else begin
                        stop_scan = 1'b1;
                    end
                end
            end
            if (!exception_fire && i_window_closed && cursor_after == i_window_length) begin
                o_window_commit_done = 1'b1;
                irq_fire = i_interrupt_pending;
            end
        end
        o_trap_valid = trap_pending;
        o_trap_interrupt = trap_interrupt;
        o_trap_epc = trap_epc;
        o_trap_cause = trap_cause;
        o_trap_tval = trap_tval;
        o_trap_slot = trap_slot;
    end
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cursor <= '0;
            window_active <= 1'b0;
            window_released <= 1'b0;
            trap_pending <= 1'b0;
            trap_interrupt <= 1'b0;
            trap_epc <= '0;
            trap_cause <= '0;
            trap_tval <= '0;
            trap_slot <= '0;
        end else if (i_window_open) begin
            cursor <= '0;
            window_active <= 1'b1;
            window_released <= 1'b0;
            trap_pending <= 1'b0;
        end else begin
            if (i_trap_ack) trap_pending <= 1'b0;
            if (window_active && !window_released && !trap_pending) begin
                cursor <= cursor_after;
                if (exception_fire) begin
                    trap_pending <= 1'b1;
                    trap_interrupt <= 1'b0;
                    trap_slot <= exception_slot;
                    trap_epc <= i_slot_pc[int'(exception_slot)*PC_W +: PC_W];
                    trap_cause <= i_slot_cause[int'(exception_slot)*CAUSE_W +: CAUSE_W];
                    trap_tval <= i_slot_tval[int'(exception_slot)*PC_W +: PC_W];
                    window_released <= 1'b1;
                end else if (o_window_commit_done) begin
                    window_released <= 1'b1;
                    if (irq_fire) begin
                        trap_pending <= 1'b1;
                        trap_interrupt <= 1'b1;
                        trap_epc <= i_next_window_pc;
                        trap_cause <= i_interrupt_cause;
                        trap_tval <= '0;
                        trap_slot <= '0;
                    end
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        assert(COMMIT_WIDTH >= 1 && WINDOW_SIZE >= 1 && COMMIT_WIDTH <= WINDOW_SIZE);
    end
    always @(posedge clk) if (reset_n && !i_window_open) begin
        assert(int'(cursor) <= WINDOW_SIZE);
        assert(int'(i_window_length) <= WINDOW_SIZE);
        assert($countones(o_commit_fire) <= COMMIT_WIDTH);
    end
    // synthesis translate_on
endmodule
