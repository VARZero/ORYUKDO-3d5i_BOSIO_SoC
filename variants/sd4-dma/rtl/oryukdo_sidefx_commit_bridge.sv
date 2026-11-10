`timescale 1ns/1ps
// Single-outstanding commit-gated side effect bridge for STORE, CSR and MMIO.
// Address/data/payload come from external queues; this control block only
// arbitrates the oldest slot, holds one request, and tracks completion.
// An error is routed to the exception controller; side effects already accepted
// by a device cannot be rolled back. External bus must preserve ack semantics.
module oryukdo_sidefx_commit_bridge #(
    parameter int SLOTS=16,
    parameter int SLOT_W=(SLOTS>1?$clog2(SLOTS):1),
    parameter int CAUSE_W=6
)(
    input wire clk, reset_n,
    input wire i_window_open,
    input wire i_commit_request,
    input wire [SLOT_W-1:0] i_commit_slot,
    output logic o_bus_valid,
    output logic [SLOT_W-1:0] o_bus_slot,
    input wire i_bus_ready,
    input wire i_bus_done,
    input wire i_bus_error,
    input wire [CAUSE_W-1:0] i_bus_error_cause,
    output logic [SLOTS-1:0] o_sidefx_done,
    output wire o_failed_response,
    output logic o_sidefx_exception_valid,
    output logic [SLOT_W-1:0] o_sidefx_exception_slot,
    output logic [CAUSE_W-1:0] o_sidefx_exception_cause
);
    logic waiting_response, waiting_accept;
    logic [SLOT_W-1:0] active_slot;
    assign o_failed_response = i_bus_done && i_bus_error && (waiting_response || (waiting_accept && i_bus_ready));
    assign o_bus_valid = waiting_accept;
    assign o_bus_slot = active_slot;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            waiting_response <= 1'b0;
            waiting_accept <= 1'b0;
            active_slot <= '0;
            o_sidefx_done <= '0;
            o_sidefx_exception_valid <= 1'b0;
            o_sidefx_exception_slot <= '0;
            o_sidefx_exception_cause <= '0;
        end else if (i_window_open) begin
            waiting_response <= 1'b0;
            waiting_accept <= 1'b0;
            active_slot <= '0;
            o_sidefx_done <= '0;
            o_sidefx_exception_valid <= 1'b0;
        end else begin
            // Hold error until a new window; the FCL must act on it.
            if (!waiting_accept && !waiting_response && i_commit_request &&
                !o_sidefx_done[i_commit_slot] && !o_sidefx_exception_valid) begin
                waiting_accept <= 1'b1;
                active_slot <= i_commit_slot;
            end
            if (waiting_accept && i_bus_ready) begin
                waiting_accept <= 1'b0;
                waiting_response <= 1'b1;
            end
            if ((waiting_response || (waiting_accept && i_bus_ready)) && i_bus_done) begin
                waiting_response <= 1'b0;
                if (i_bus_error) begin
                    o_sidefx_exception_valid <= 1'b1;
                    o_sidefx_exception_slot <= active_slot;
                    o_sidefx_exception_cause <= i_bus_error_cause;
                end else o_sidefx_done[active_slot] <= 1'b1;
            end
        end
    end
endmodule
