`timescale 1ns/1ps
// Single-cycle-per-slot replay of a Flow Window's rename log. This avoids
// an SLOTS-deep combinational selection tree in the FCL critical path.
// Input metadata is held stable until o_valid is acknowledged.
module oryukdo_exception_prefix_map #(
    parameter int SLOTS=16, LOGICAL_REGS=32, PHY_W=6,
    parameter int LOG_W=(LOGICAL_REGS>1?$clog2(LOGICAL_REGS):1),
    parameter int SLOT_W=(SLOTS>1?$clog2(SLOTS):1),
    parameter int MAP_W=LOGICAL_REGS*PHY_W
)(
    input wire clk,reset_n,
    input wire i_start,
    input wire [$clog2(SLOTS+1)-1:0] i_exception_slot,
    input wire [MAP_W-1:0] i_baseline_map,
    input wire [SLOTS-1:0] i_renamed,
    input wire [SLOTS*LOG_W-1:0] i_rd,
    input wire [SLOTS*PHY_W-1:0] i_phy,
    output logic o_busy,o_valid,
    output logic [MAP_W-1:0] o_map,
    input wire i_ack
);
    logic [$clog2(SLOTS+1)-1:0] cursor,boundary;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cursor<='0;boundary<='0;o_busy<=1'b0;o_valid<=1'b0;o_map<='0;
        end else begin
            if (o_valid && i_ack) o_valid<=1'b0;
            if (i_start && !o_busy && !o_valid) begin
                boundary<=i_exception_slot;
                cursor<='0;
                o_map<=i_baseline_map;
                o_busy<=1'b1;
            end else if (o_busy) begin
                if (cursor==boundary) begin
                    o_busy<=1'b0;
                    o_valid<=1'b1;
                end else begin
                    if (i_renamed[int'(cursor)])
                        o_map[int'(i_rd[int'(cursor)*LOG_W +: LOG_W])*PHY_W +: PHY_W] <=
                            i_phy[int'(cursor)*PHY_W +: PHY_W];
                    cursor<=cursor+1'b1;
                end
            end
        end
    end
endmodule
