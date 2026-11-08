`timescale 1ns/1ps
// ORYUKDO Gen3 replaceable branch-prediction boundary.
// Default: static not-taken for conditional branches.
// Other control transfers may provide an independently resolved early target.
// Prediction state and checkpoint management belong to FCL, not this wrapper.
module oryukdo_branch_predictor #(
    parameter int PC_W = 32,
    parameter int PC_STEP = 4,
    parameter int TAG_W = 40,
    parameter int FETCH_WIDTH = 3,
    parameter int RESOLVE_WIDTH = 1,
    parameter bit USE_CUSTOM = 1'b0
) (
    // Prediction queries are valid only for branch instructions. Each lane
    // is independent; upstream retains its query if a custom predictor stalls.
    input  logic [FETCH_WIDTH-1:0]         i_predict_valid,
    input  logic [FETCH_WIDTH*PC_W-1:0]    i_predict_pc,
    input  logic [FETCH_WIDTH*TAG_W-1:0]   i_predict_tag,
    output logic [FETCH_WIDTH-1:0]         o_predict_ready,
    output logic [FETCH_WIDTH-1:0]         o_predict_valid,
    output logic [FETCH_WIDTH*TAG_W-1:0]   o_predict_tag,
    output logic [FETCH_WIDTH-1:0]         o_predict_taken,
    output logic [FETCH_WIDTH*PC_W-1:0]    o_predict_target,

    // A plugin can be combinational or registered, but must honor the
    // valid/ready query contract. Predictions only transfer on handshake.
    output logic [FETCH_WIDTH-1:0]         o_custom_query_valid,
    output logic [FETCH_WIDTH*PC_W-1:0]    o_custom_query_pc,
    output logic [FETCH_WIDTH*TAG_W-1:0]   o_custom_query_tag,
    input  logic [FETCH_WIDTH-1:0]         i_custom_query_ready,
    // Custom predictor holds response valid/data until ready is asserted.
    output logic [FETCH_WIDTH-1:0]        o_custom_prediction_ready,
    input  logic [FETCH_WIDTH-1:0]         i_custom_prediction_valid,
    input  logic [FETCH_WIDTH*TAG_W-1:0]   i_custom_prediction_tag,
    input  logic [FETCH_WIDTH-1:0]         i_custom_prediction_taken,
    input  logic [FETCH_WIDTH*PC_W-1:0]    i_custom_prediction_target,

    // Actual EX-resolved outcomes are forwarded for predictor training.
    input logic [FETCH_WIDTH-1:0] i_response_consume,
    input  logic [RESOLVE_WIDTH-1:0]       i_resolve_valid,
    input  logic [RESOLVE_WIDTH*TAG_W-1:0] i_resolve_tag,
    input  logic [RESOLVE_WIDTH*PC_W-1:0]  i_resolve_pc,
    input  logic [RESOLVE_WIDTH-1:0]       i_resolve_taken,
    input  logic [RESOLVE_WIDTH*PC_W-1:0]  i_resolve_target,
    input  logic [RESOLVE_WIDTH-1:0]       i_resolve_squashed,
    output logic [RESOLVE_WIDTH-1:0]       o_custom_update_valid,
    output logic [RESOLVE_WIDTH*TAG_W-1:0] o_custom_update_tag,
    output logic [RESOLVE_WIDTH*PC_W-1:0]  o_custom_update_pc,
    output logic [RESOLVE_WIDTH-1:0]       o_custom_update_taken,
    output logic [RESOLVE_WIDTH*PC_W-1:0]  o_custom_update_target
);
    always_comb begin
        o_custom_prediction_ready=i_response_consume;
        o_custom_query_valid = '0;
        o_custom_query_pc = i_predict_pc;
        o_custom_query_tag = i_predict_tag;
        o_predict_ready = '0;
        o_predict_valid = '0;
        o_predict_tag = '0;
        o_predict_taken = '0;
        o_predict_target = '0;
        o_custom_update_valid = i_resolve_valid & ~i_resolve_squashed;
        o_custom_update_tag = i_resolve_tag;
        o_custom_update_pc = i_resolve_pc;
        o_custom_update_taken = i_resolve_taken;
        o_custom_update_target = i_resolve_target;
        if (USE_CUSTOM) begin
            o_custom_query_valid = i_predict_valid;
            o_predict_ready = i_custom_query_ready;
            o_predict_valid = i_custom_prediction_valid;
            o_predict_tag = i_custom_prediction_tag;
            o_predict_taken = i_custom_prediction_taken;
            for (int lane=0;lane<FETCH_WIDTH;lane++)
                o_predict_target[lane*PC_W +: PC_W] = i_custom_prediction_taken[lane] ?
                    i_custom_prediction_target[lane*PC_W +: PC_W] :
                    i_custom_prediction_tag[lane*TAG_W +: PC_W] + PC_W'(PC_STEP);
        end else begin
            o_predict_ready = '1;
            o_predict_valid = i_predict_valid;
            o_predict_tag = i_predict_tag;
            // Static not taken: target output is the fall-through PC (+4).
            for (int lane = 0; lane < FETCH_WIDTH; lane++) begin
                o_predict_target[lane*PC_W +: PC_W] =
                    i_predict_pc[lane*PC_W +: PC_W] + PC_W'(PC_STEP);
            end
        end
    end
endmodule
