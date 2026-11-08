`timescale 1ns/1ps
// RS/LSQ -> EX boundary. The FCL supplies exact per-lane kill decisions;
// this block MUST NOT calculate the age of instructions from their PC.
// Killed instructions consume their upstream queue entry, but do not reach EX.
module oryukdo_issue_guard #(
    parameter int LANES = 5,
    parameter int DATA_W = 96
) (
    input  wire [LANES-1:0] i_valid,
    output wire [LANES-1:0] o_get,
    input  wire [LANES*DATA_W-1:0] i_data,
    input  wire [LANES-1:0] i_kill,
    input  wire [LANES-1:0] i_ex_get,
    output wire [LANES-1:0] o_ex_valid,
    output wire [LANES*DATA_W-1:0] o_ex_data,
    output wire [LANES-1:0] o_discard_fire
);
    assign o_ex_valid = i_valid & ~i_kill;
    assign o_ex_data = i_data;
    assign o_discard_fire = i_valid & i_kill;
    assign o_get = o_discard_fire | (o_ex_valid & i_ex_get);
endmodule
