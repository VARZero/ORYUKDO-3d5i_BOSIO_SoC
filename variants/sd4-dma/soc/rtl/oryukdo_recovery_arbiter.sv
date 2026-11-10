`timescale 1ns/1ps
// Unified branch/exception/interrupt recovery request arbitration.
// Requests must be already age-qualified by the ordered FCL commit/branch head.
// Trap has priority over a younger branch; caller is responsible for eliminating
// wrong-path exceptions before asserting i_exception_valid.
module oryukdo_recovery_arbiter #(
    parameter int PC_W=32,
    parameter int TAG_W=8,
    parameter int CAUSE_W=6
)(
    input wire clk, reset_n,
    input wire i_branch_valid,
    input wire [TAG_W-1:0] i_branch_tag,
    input wire [PC_W-1:0] i_branch_target,
    input wire i_exception_valid,
    input wire [TAG_W-1:0] i_exception_tag,
    input wire [PC_W-1:0] i_exception_pc,
    input wire [CAUSE_W-1:0] i_exception_cause,
    input wire [PC_W-1:0] i_exception_tval,
    input wire i_interrupt_valid,
    input wire [PC_W-1:0] i_interrupt_resume_pc,
    input wire [CAUSE_W-1:0] i_interrupt_cause,
    input wire [TAG_W-1:0] i_interrupt_boundary_tag,
    input wire [PC_W-1:0] i_trap_vector_pc,
    input wire i_drain_done,
    input wire i_rename_restored,
    input wire i_trap_csr_done,
    output logic o_recovery_busy,
    output logic [1:0] o_recovery_type,
    output logic [TAG_W-1:0] o_boundary_tag,
    output logic o_boundary_inclusive,
    output logic [PC_W-1:0] o_redirect_pc,
    output logic [PC_W-1:0] o_trap_epc,
    output logic [CAUSE_W-1:0] o_trap_cause,
    output logic [PC_W-1:0] o_trap_tval,
    output logic o_kill_active,
    output logic o_rename_restore_request,
    output logic o_trap_csr_request,
    output logic o_redirect_valid
);
    typedef enum logic [1:0] {IDLE=2'd0, DRAIN=2'd1, RENAME=2'd2, TRAP_CSR=2'd3} state_t;
    state_t state;
    // Recovery types 0=branch, 1=exception, 2=interrupt.
    assign o_recovery_busy = (state != IDLE);
    assign o_kill_active = (state == DRAIN);
    assign o_rename_restore_request = (state == RENAME);
    assign o_trap_csr_request = (state == TRAP_CSR);
    assign o_redirect_valid = (state == TRAP_CSR && i_trap_csr_done) ||
                              (state == RENAME && i_rename_restored && o_recovery_type == 2'd0);
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            state <= IDLE;
            o_recovery_type <= 2'd0;
            o_boundary_tag <= '0;
            o_boundary_inclusive <= 1'b0;
            o_redirect_pc <= '0;
            o_trap_epc <= '0;
            o_trap_cause <= '0;
            o_trap_tval <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (i_exception_valid) begin
                        o_recovery_type <= 2'd1;
                        o_boundary_tag <= i_exception_tag;
                        o_boundary_inclusive <= 1'b1;
                        o_trap_epc <= i_exception_pc;
                        o_trap_cause <= i_exception_cause;
                        o_trap_tval <= i_exception_tval;
                        o_redirect_pc <= i_trap_vector_pc;
                        state <= DRAIN;
                    end else if (i_branch_valid) begin
                        o_recovery_type <= 2'd0;
                        o_boundary_tag <= i_branch_tag;
                        o_boundary_inclusive <= 1'b0;
                        o_redirect_pc <= i_branch_target;
                        state <= DRAIN;
                    end else if (i_interrupt_valid) begin
                        o_recovery_type <= 2'd2;
                        o_boundary_tag <= i_interrupt_boundary_tag;
                        o_boundary_inclusive <= 1'b0;
                        o_trap_epc <= i_interrupt_resume_pc;
                        o_trap_cause <= i_interrupt_cause;
                        o_trap_tval <= '0;
                        o_redirect_pc <= i_trap_vector_pc;
                        state <= DRAIN;
                    end
                end
                DRAIN: if (i_drain_done) state <= RENAME;
                RENAME: if (i_rename_restored) begin
                    if (o_recovery_type == 2'd0) state <= IDLE;
                    else begin
                        // Delegation and vectored targets depend on the captured trap cause.
                        o_redirect_pc <= i_trap_vector_pc;
                        state <= TRAP_CSR;
                    end
                end
                TRAP_CSR: if (i_trap_csr_done) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
