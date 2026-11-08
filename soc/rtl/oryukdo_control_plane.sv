`timescale 1ns/1ps
// Integrated SPECULATIVE CONTROL PLANE for ORYUKDO Gen3.
// NOT a CPU top: the NEL, PRM, FDU and LSQ must implement the interfaces below.
// The contract intentionally has no automatic window recycle: i_drain_done
// must assert only after all killed and older in-flight operations have been
// accounted for, including memory responses and pending PHYREG ownership.
module oryukdo_control_plane #(
    parameter int PC_W=32, PC_STEP=4, FLOWS=8, SLOTS=16, DECODE=3,
    parameter int RESOLVE_LANES=1,
    parameter int PHY_W=6, LOGICAL_REGS=32, CAUSE_W=6,
    parameter int FLOW_W=(FLOWS>1?$clog2(FLOWS):1),
    parameter int SLOT_W=(SLOTS>1?$clog2(SLOTS):1),
    parameter int TAG_W=FLOW_W+PC_W,
    parameter int MAP_W=LOGICAL_REGS*PHY_W,
    parameter int COUNT_W=$clog2(SLOTS+1)
)(
    input wire clk,reset_n,
    // NEL checkpoint allocation / backpressure
    input wire i_branch_candidate_valid,
    input wire i_checkpoint_valid,
    output wire o_checkpoint_ready,
    input wire [TAG_W-1:0] i_checkpoint_tag,
    input wire [PC_W-1:0] i_predicted_next_pc,
    input wire [MAP_W-1:0] i_checkpoint_map,
    // Out-of-order EX branch outcomes
    input wire [RESOLVE_LANES-1:0] i_branch_result_valid,
    input wire [RESOLVE_LANES*TAG_W-1:0] i_branch_result_tag,
    input wire [RESOLVE_LANES*PC_W-1:0] i_branch_result_pc,
    // Oldest FDU window, including ordered prefix bookkeeping
    input wire [FLOW_W-1:0] i_oldest_flow,
    input wire i_window_open, i_window_closed,
    input wire [COUNT_W-1:0] i_window_length,
    input wire [SLOTS-1:0] i_slot_valid,i_slot_done,i_slot_squashed,
    input wire [SLOTS-1:0] i_slot_exception,i_slot_sidefx,
    input wire [SLOTS*PC_W-1:0] i_slot_pc,i_slot_tval,
    input wire [SLOTS*CAUSE_W-1:0] i_slot_cause,
    input wire [PC_W-1:0] i_next_window_pc,
    input wire [PC_W-1:0] i_oldest_start_pc,
    input wire i_interrupt_pending,
    input wire [CAUSE_W-1:0] i_interrupt_cause,
    input wire [PC_W-1:0] i_trap_vector_pc,
    // FDU/LSQ/EX drain contract; DO NOT assert on mere squash request.
    input wire i_drain_done,
    // For exception / interrupt, caller must provide prefix-reconstructed map.
    input wire [MAP_W-1:0] i_trap_baseline_map,
    input wire [SLOTS-1:0] i_trap_renamed,
    input wire [SLOTS*((LOGICAL_REGS>1)?$clog2(LOGICAL_REGS):1)-1:0] i_trap_rename_rd,
    input wire [SLOTS*PHY_W-1:0] i_trap_rename_phy,
    // NEL incremental map write handshake, PRM must protect checkpoint refs.
    output wire o_map_write_valid,
    output wire [(LOGICAL_REGS>1?$clog2(LOGICAL_REGS):1)-1:0] o_map_write_logreg,
    output wire [PHY_W-1:0] o_map_write_phyreg,
    input wire i_map_write_ready,
    // Commit-gated side effect bus (Store/CSR/non-spec MMIO).
    output wire o_sidefx_valid, o_failed_response,
    output wire [SLOT_W-1:0] o_sidefx_slot,
    input wire i_sidefx_ready, i_sidefx_done, i_sidefx_error,
    input wire [CAUSE_W-1:0] i_sidefx_error_cause,
    // Trap CSR writes must be acknowledged, and happen before redirect.
    output wire o_trap_csr_request,
    output wire [PC_W-1:0] o_trap_epc,o_trap_tval,
    output wire [CAUSE_W-1:0] o_trap_cause,
    input wire i_trap_csr_done,
    // Squash boundary broadcast to guards and FDU/LSQ.
    output wire o_kill_active,
    output wire [TAG_W-1:0] o_kill_boundary_tag,
    output wire o_kill_inclusive,
    output wire [FLOW_W-1:0] o_kill_oldest_flow,
    output wire o_rename_stall,
    output wire o_redirect_valid,
    output wire [PC_W-1:0] o_redirect_pc,
    output wire [SLOTS-1:0] o_commit_fire,
    output wire o_window_commit_done,
    output wire [1:0] o_recovery_kind,
    output wire o_recovery_busy,
    output wire o_speculative_branches_empty
);
    wire branch_recovery_valid;
    wire [TAG_W-1:0] branch_recovery_tag;
    wire [PC_W-1:0] branch_recovery_target;
    wire [MAP_W-1:0] branch_restore_map;
    wire recovery_busy,mapper_busy,mapper_done,restore_req,arb_redirect_valid;
    wire [1:0] recovery_type;
    wire [TAG_W-1:0] boundary_tag;
    wire boundary_inclusive;
    wire [PC_W-1:0] arb_redirect_pc,trap_epc,trap_tval,arb_trap_epc,arb_trap_tval;
    wire [CAUSE_W-1:0] trap_cause,arb_trap_cause;
    wire trap_valid,trap_irq,trap_ack;
    wire [SLOT_W-1:0] trap_slot;
    wire sidefx_req;
    wire [SLOT_W-1:0] sidefx_req_slot;
    wire [SLOTS-1:0] sidefx_finished;
    wire sidefx_exception_valid;
    wire [SLOT_W-1:0] sidefx_exception_slot;
    wire [CAUSE_W-1:0] sidefx_exception_cause;
    wire [PC_W-1:0] trap_source_epc,trap_source_tval;
    wire [SLOTS*CAUSE_W-1:0] effective_cause;
    wire [SLOTS*PC_W-1:0] effective_tval;
    wire [SLOTS-1:0] effective_exception;
    generate for (genvar a=0; a<SLOTS; a++) begin : G_EXCEPTION_META
        assign effective_exception[a] = i_slot_exception[a] ||
            (sidefx_exception_valid && sidefx_exception_slot == SLOT_W'(a));
        assign effective_cause[a*CAUSE_W +: CAUSE_W] =
            (sidefx_exception_valid && sidefx_exception_slot == SLOT_W'(a)) ?
            sidefx_exception_cause : i_slot_cause[a*CAUSE_W +: CAUSE_W];
        assign effective_tval[a*PC_W +: PC_W] = i_slot_tval[a*PC_W +: PC_W];
    end endgenerate
    wire [CAUSE_W-1:0] trap_source_cause;
    wire [TAG_W-1:0] trap_source_tag;
    wire recovery_branch_done;
    wire [TAG_W-1:0] head_branch;
    wire [COUNT_W-1:0] commit_cursor;
    wire [PC_W-1:0] branch_offset = head_branch[0 +: PC_W] - i_oldest_start_pc;
    wire [SLOT_W-1:0] branch_slot = SLOT_W'(branch_offset/PC_STEP);
    wire branch_in_oldest = !o_speculative_branches_empty && head_branch[TAG_W-1:PC_W]==i_oldest_flow;
    wire [SLOTS-1:0] eligible;
    for (genvar s=0;s<SLOTS;s++) begin : G_COMMIT_BARRIER
        assign eligible[s] = i_slot_valid[s] && !recovery_busy &&
            (!branch_in_oldest || s<int'(branch_slot) ||
            (SLOT_W'(s)==branch_slot && effective_exception[s]));
    end
    // The commit cursor is loaded at the opening edge. During that edge it
    // still describes the previous window, even though tags name the new one.
    wire take_branch = !i_window_open && branch_recovery_valid && branch_in_oldest && !trap_valid &&
        COUNT_W'(branch_slot)==commit_cursor &&
        !effective_exception[int'(commit_cursor)];
    wire [$clog2(FLOWS*4+1)-1:0] branch_count;
    assign o_speculative_branches_empty=(branch_count==0);
    wire prefix_busy,prefix_ready,prefix_start,prefix_ack;
    wire [MAP_W-1:0] prefix_map;
    wire [MAP_W-1:0] active_restore_map = (recovery_type==2'd0) ? branch_restore_map : prefix_map;
    assign o_rename_stall = recovery_busy || trap_valid || take_branch || (i_branch_candidate_valid && !o_checkpoint_ready);
    assign o_recovery_kind=recovery_type;
    assign o_recovery_busy=recovery_busy;
    assign o_kill_boundary_tag=boundary_tag;
    assign o_kill_inclusive=boundary_inclusive;
    assign o_kill_oldest_flow=i_oldest_flow;
    assign o_redirect_valid=arb_redirect_valid;
    assign o_redirect_pc=arb_redirect_pc;
    assign o_trap_epc=arb_trap_epc;
    assign o_trap_cause=arb_trap_cause;
    assign o_trap_tval=arb_trap_tval;
    // A branch checkpoint holds the entire post-branch rename map.
    oryukdo_branch_recovery #(
        .PC_W(PC_W), .FLOW_WINDOWS(FLOWS),.SLOT_W(PC_W),
        .PHY_W(PHY_W),.LOGICAL_REGS(LOGICAL_REGS),
        .RESOLVE_LANES(RESOLVE_LANES),.DEPTH(FLOWS*4),.PER_WINDOW(4)
    ) U_BRANCH_RECOVERY (
        .clk(clk),.reset_n(reset_n),.i_push(i_checkpoint_valid),
        .o_push_ready(o_checkpoint_ready),.i_push_tag(i_checkpoint_tag),
        .i_push_predicted_next_pc(i_predicted_next_pc),
        .i_push_rename_map(i_checkpoint_map),
        .i_resolve_valid(i_branch_result_valid),.i_resolve_tag(i_branch_result_tag),
        .i_resolve_next_pc(i_branch_result_pc),
        .o_recovery_valid(branch_recovery_valid),
        .o_recovery_tag(branch_recovery_tag),.o_redirect_pc(branch_recovery_target),
        .o_restore_map(branch_restore_map),
        .o_head_tag(head_branch),.i_trap_flush(trap_ack),.i_recovery_done(recovery_branch_done),.o_outstanding(branch_count)
    );
    // Sequential prefix commit. The real FDU provides the stable oldest
    // window slot metadata; commit never skips an incomplete older slot.
    oryukdo_commit_trap_controller #(
        .WINDOW_SIZE(SLOTS),.COMMIT_WIDTH(DECODE),.PC_W(PC_W),.CAUSE_W(CAUSE_W)
    ) U_COMMIT (
        .clk(clk),.reset_n(reset_n),.i_window_open(i_window_open),
        .i_window_closed(i_window_closed),.i_window_length(i_window_length),
        .i_slot_valid(eligible),
        .i_slot_done(i_slot_done),
        .i_slot_squashed(i_slot_squashed),
        .i_slot_exception(effective_exception),
        .i_slot_sidefx(i_slot_sidefx),.i_sidefx_done(sidefx_finished),
        .i_slot_pc(i_slot_pc),.i_slot_cause(effective_cause),
        .i_slot_tval(effective_tval),.i_next_window_pc(i_next_window_pc),
        .i_interrupt_pending(i_interrupt_pending && (|(i_slot_valid & ~i_slot_squashed)) && !recovery_busy),
        .i_interrupt_cause(i_interrupt_cause),.i_trap_ack(trap_ack),
        .o_commit_cursor(commit_cursor),.o_commit_fire(o_commit_fire),
        .o_sidefx_request(sidefx_req),.o_sidefx_slot(sidefx_req_slot),
        .o_window_commit_done(o_window_commit_done),
        .o_trap_valid(trap_valid),.o_trap_interrupt(trap_irq),
        .o_trap_epc(trap_epc),.o_trap_cause(trap_cause),
        .o_trap_tval(trap_tval),.o_trap_slot(trap_slot)
    );
    oryukdo_sidefx_commit_bridge #(.SLOTS(SLOTS),.CAUSE_W(CAUSE_W)) U_SIDEFX (
        .clk(clk),.reset_n(reset_n),.i_window_open(i_window_open),
        .i_commit_request(sidefx_req),.i_commit_slot(sidefx_req_slot),
        .o_bus_valid(o_sidefx_valid),.o_bus_slot(o_sidefx_slot),
        .i_bus_ready(i_sidefx_ready),.i_bus_done(i_sidefx_done),
        .i_bus_error(i_sidefx_error),.i_bus_error_cause(i_sidefx_error_cause),
        .o_failed_response(o_failed_response),.o_sidefx_done(sidefx_finished),
        .o_sidefx_exception_valid(sidefx_exception_valid),
        .o_sidefx_exception_slot(sidefx_exception_slot),
        .o_sidefx_exception_cause(sidefx_exception_cause)
    );
    assign trap_source_epc=trap_epc;
    assign trap_source_cause=trap_cause;
    assign trap_source_tval=trap_tval;
    assign trap_source_tag={i_oldest_flow,
        (i_oldest_start_pc + PC_W'(trap_slot)*PC_W'(PC_STEP))};
    logic prefix_started;
    always_ff @(posedge clk) begin
        if (!reset_n) prefix_started<=1'b0;
        else if (!trap_valid) prefix_started<=1'b0;
        else if (prefix_start) prefix_started<=1'b1;
    end
    assign prefix_start=trap_valid && !prefix_started && !prefix_ready && !prefix_busy;
    assign prefix_ack=trap_ack;
    oryukdo_exception_prefix_map #(
        .SLOTS(SLOTS),.LOGICAL_REGS(LOGICAL_REGS),.PHY_W(PHY_W)
    ) U_EXCEPTION_PREFIX_MAP (
        .clk(clk),.reset_n(reset_n),.i_start(prefix_start),
        .i_exception_slot(trap_irq ? i_window_length : COUNT_W'(trap_slot)),.i_baseline_map(i_trap_baseline_map),
        .i_renamed(i_trap_renamed & ~i_slot_squashed),.i_rd(i_trap_rename_rd),
        .i_phy(i_trap_rename_phy),.o_busy(prefix_busy),
        .o_valid(prefix_ready),.o_map(prefix_map),.i_ack(prefix_ack)
    );
    assign trap_ack=trap_valid && !recovery_busy && prefix_ready;
    oryukdo_recovery_arbiter #(.PC_W(PC_W),.TAG_W(TAG_W),.CAUSE_W(CAUSE_W)) U_RECOVERY_ARB (
        .clk(clk),.reset_n(reset_n),
        .i_branch_valid(take_branch && !trap_ack),
        .i_branch_tag(branch_recovery_tag),.i_branch_target(branch_recovery_target),
        .i_exception_valid(trap_ack && !trap_irq),
        .i_exception_tag(trap_source_tag),.i_exception_pc(trap_source_epc),
        .i_exception_cause(trap_source_cause),.i_exception_tval(trap_source_tval),
        .i_interrupt_valid(trap_ack && trap_irq),
        .i_interrupt_resume_pc(trap_epc),.i_interrupt_cause(trap_cause),
        .i_interrupt_boundary_tag({i_oldest_flow,i_oldest_start_pc + (PC_W'(i_window_length)-1'b1)*PC_W'(PC_STEP)}),
        .i_trap_vector_pc(i_trap_vector_pc),.i_drain_done(i_drain_done),
        .i_rename_restored(mapper_done),.i_trap_csr_done(i_trap_csr_done),
        .o_recovery_busy(recovery_busy),.o_recovery_type(recovery_type),
        .o_boundary_tag(boundary_tag),.o_boundary_inclusive(boundary_inclusive),
        .o_redirect_pc(arb_redirect_pc),.o_trap_epc(arb_trap_epc),
        .o_trap_cause(arb_trap_cause),.o_trap_tval(arb_trap_tval),
        .o_kill_active(o_kill_active),.o_rename_restore_request(restore_req),
        .o_trap_csr_request(o_trap_csr_request),.o_redirect_valid(arb_redirect_valid)
    );
    // Start the serialized mapper only once per recovery. Arbiter holds
    // RENAME until mapper_done; mapper only accepts i_start when idle.
    logic restore_started;
    always_ff @(posedge clk) begin
        if (!reset_n) restore_started<=1'b0;
        else if (!restore_req) restore_started<=1'b0;
        else if (!restore_started) restore_started<=1'b1;
    end
    oryukdo_recovery_mapper #(.LOGICAL_REGS(LOGICAL_REGS),.PHY_W(PHY_W)) U_MAP_REPLAY (
        .clk(clk),.reset_n(reset_n),.i_start(restore_req && !restore_started),
        .i_snapshot(active_restore_map),.o_busy(mapper_busy),.o_done(mapper_done),
        .o_write_valid(o_map_write_valid),.o_logical_reg(o_map_write_logreg),
        .o_phyreg(o_map_write_phyreg),.i_write_ready(i_map_write_ready)
    );
    assign recovery_branch_done=arb_redirect_valid && recovery_type==2'd0;
endmodule
