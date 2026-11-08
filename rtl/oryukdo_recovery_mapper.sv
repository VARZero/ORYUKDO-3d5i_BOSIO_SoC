`timescale 1ns/1ps
// Serialized replay of a stored rename map: one logical register per cycle.
// NEL must stop new rename while o_busy; PRM must retain all referenced PHYREGs.
// A downstream map write has an acknowledge pulse. This is a boundary adapter,
// not a complete NEL/PRM recovery implementation.
module oryukdo_recovery_mapper #(
    parameter int LOGICAL_REGS=32, PHY_W=6,
    localparam int INDEX_W=LOGICAL_REGS>1?$clog2(LOGICAL_REGS):1,
    localparam int MAP_W=LOGICAL_REGS*PHY_W
)(
    input wire clk, reset_n, i_start,
    input wire [MAP_W-1:0] i_snapshot,
    output logic o_busy, o_done,
    output wire o_write_valid,
    output wire [INDEX_W-1:0] o_logical_reg,
    output wire [PHY_W-1:0] o_phyreg,
    input wire i_write_ready
);
    logic [MAP_W-1:0] snapshot;
    logic [INDEX_W-1:0] index;
    assign o_write_valid = o_busy;
    assign o_logical_reg = index;
    assign o_phyreg = snapshot[int'(index)*PHY_W +: PHY_W];
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            snapshot<='0; index<='0; o_busy<=0; o_done<=0;
        end else begin
            o_done <= 0;
            if (i_start && !o_busy) begin
                snapshot <= i_snapshot;
                index <= '0;
                o_busy <= 1;
            end else if (o_busy && i_write_ready) begin
                if (index == INDEX_W'(LOGICAL_REGS-1)) begin
                    o_busy <= 0;
                    o_done <= 1;
                end else index <= index+1'b1;
            end
        end
    end
endmodule
