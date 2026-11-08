`timescale 1ns/1ps
// Common boundary classifier for issue, result and LSQ queues.
// A boundary is a window-local instruction INDEX, not the numerical PC.
// Flow identifiers may only be recycled after ALL associated responses drain.
module oryukdo_recovery_boundary #(
    parameter int FLOWS=8,
    parameter int SLOT_W=4,
    parameter int PC_W=32,
    parameter int LANES=5,
    parameter bit WRAPPING_PC=0,
    parameter int FLOW_W=(FLOWS>1?$clog2(FLOWS):1),
    parameter int TAG_W=FLOW_W+SLOT_W
)(
    input wire i_recovery_active,
    input wire [FLOW_W-1:0] i_oldest_flow,
    input wire [TAG_W-1:0] i_boundary_tag,
    input wire i_boundary_inclusive,
    input wire [LANES-1:0] i_candidate_valid,
    input wire [LANES*TAG_W-1:0] i_candidate_tag,
    output logic [LANES-1:0] o_kill
);
    // The youngest active flow might wrap through zero. Compare age relative
    // to the oldest allocated flow, never compare flow IDs numerically.
    localparam int DIST_W=$clog2(FLOWS+1);
    logic [DIST_W-1:0] boundary_distance;
    always_comb begin
        boundary_distance = DIST_W'((int'(i_boundary_tag[TAG_W-1:SLOT_W])
                              +FLOWS-int'(i_oldest_flow))%FLOWS);
        o_kill='0;
        for (int l=0;l<LANES;l++) begin
            if (i_recovery_active && i_candidate_valid[l]) begin
                if (DIST_W'((int'(i_candidate_tag[l*TAG_W+SLOT_W +: FLOW_W])
                         +FLOWS-int'(i_oldest_flow))%FLOWS) > boundary_distance)
                    o_kill[l]=1'b1;
                else if (DIST_W'((int'(i_candidate_tag[l*TAG_W+SLOT_W +: FLOW_W])
                         +FLOWS-int'(i_oldest_flow))%FLOWS) == boundary_distance)
                    o_kill[l] = (WRAPPING_PC ?
                        ($signed(i_candidate_tag[l*TAG_W +: SLOT_W]-i_boundary_tag[0 +: SLOT_W]) > 0) :
                        (i_candidate_tag[l*TAG_W +: SLOT_W] > i_boundary_tag[0 +: SLOT_W])) ||
                         (i_boundary_inclusive &&
                          i_candidate_tag[l*TAG_W +: SLOT_W] == i_boundary_tag[0 +: SLOT_W]);
            end
        end
    end
endmodule
