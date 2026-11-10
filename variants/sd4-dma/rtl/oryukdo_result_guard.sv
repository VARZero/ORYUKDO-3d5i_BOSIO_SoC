`timescale 1ns/1ps
// EX -> WBC result boundary; successful results bypass unchanged.
// All discarded completions must be acknowledged to FDU separately.
// This filter does not discard branch-resolution metadata until FCL has
// captured any branch-resolution event that could cause recovery.
module oryukdo_result_guard #(
    parameter int LANES = 5,
    parameter int DATA_W = 42,
    parameter int TAG_W = 35
) (
    input  wire [LANES-1:0] i_valid,
    input  wire [LANES*DATA_W-1:0] i_data,
    input  wire [LANES*TAG_W-1:0] i_tag,
    input  wire [LANES-1:0] i_kill,
    output wire [LANES-1:0] o_wbc_valid,
    output wire [LANES*DATA_W-1:0] o_wbc_data,
    output wire [LANES-1:0] o_discard_valid,
    output wire [LANES*TAG_W-1:0] o_discard_tag
);
    assign o_wbc_valid = i_valid & ~i_kill;
    assign o_wbc_data = i_data;
    assign o_discard_valid = i_valid & i_kill;
    assign o_discard_tag = i_tag;
endmodule
