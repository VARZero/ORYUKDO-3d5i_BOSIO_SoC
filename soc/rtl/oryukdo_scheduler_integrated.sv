`timescale 1ns/1ps
module oryukdo_gen3_scheduler #(
    // Instruction Set Parameters
    parameter bit ASYNC_PORT_ISOLATION = 1,
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 3,
    parameter int STRUCT_INST_STATE_ENTRIES             = 128,
    parameter int STRUCT_PHYREGS                        = 64,
    parameter int STRUCT_EX_PATH                        = 3,
    parameter int STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]   = {1, 3, 1},
    parameter int STRUCT_EX_CORES                       = 5,
    parameter int STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES] = {1, 1, 1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM              = 5,
    parameter int STRUCT_EX_BRANCH                      = 1,
    parameter int STRUCT_PRM_ENTRY_UPDATE               = 5,
    parameter int STRUCT_PRM_ENTRY_BUFFER               = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG              = 4,
    parameter int STRUCT_FLOW_WINDOWS                   = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE              = 16,

    // Wakeup bandwidth, stored-instruction issue bandwidth and SRAM banking
    // are independent. Banks use low entry-number bits (power of two).
    parameter int STRUCT_IST_ISSUE_WIDTH               = STRUCT_EX_CORES,
    parameter int STRUCT_IST_BANKS                     = 1 << $clog2(
        (STRUCT_DECODE_NEW_INST > STRUCT_IST_ISSUE_WIDTH) ? STRUCT_DECODE_NEW_INST : STRUCT_IST_ISSUE_WIDTH),

    // Minimum instruction capacity per RS EX-path FIFO (not data bit width).
    parameter int STRUCT_RS_FIFO_WIDTH                = 128,

    // Optional serialized LD/ST ordering. All instructions on this EX path
    // participate; completion must include stores (rd=0) in the WBC results.
    parameter bit ENABLE_LSQ                          = 1'b1,
    parameter bit USE_CUSTOM_BRANCH_PREDICTOR          = 1'b0,
    parameter int STRUCT_LSQ_ENTRIES                  = 32,
    parameter int STRUCT_LSQ_EX_PATH                  = 2,

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_INST_STATE_ENTRIES  = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = (STRUCT_FLOW_WINDOWS > 1)? $clog2(STRUCT_FLOW_WINDOWS) : 1,
    localparam int _BITWIDTH_READY_PRM                  = _BITWIDTH_STRUCT_INST_STATE_ENTRIES+_BITWIDTH_STRUCT_PHYREGS,
    localparam int _BITWIDTH_FLOW_WINDOWS_PC            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Flag
                                                         + 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_BRANCH_RESULT      = IS_INST_PC_BITWIDTH+_BITWIDTH_FLOW_WINDOWS_PC,
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  wire                                                                              clk,
    input  wire                                                                              reset_n,

    // PC Request
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                                 o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_FLOW_WINDOWS_PC)-1:0]                   o_im_req_pc,
    
    // Instruction Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_im_recv_inst_valid,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                                 o_im_recv_inst_get,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_FLOW_WINDOWS_PC)-1:0]                   i_im_recv_pc,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_BITWIDTH)-1:0]                            i_im_recv_inst,
    
    // Decoder Info Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_exception,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                  i_nel_decode_expath,
    input  wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                  i_nel_decode_microop,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_IS_INST_REGS) )-1:0]                    i_nel_decode_rd,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_newreg,
    input  wire [((STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS) *(_BITWIDTH_IS_INST_REGS) )-1:0] i_nel_decode_rs,
    input  wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                               i_nel_decode_imm,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_jump,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_jump_reg,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_branch,
    
    // EX Inst Push (RS Out)
    output wire [STRUCT_EX_CORES-1:0]                                                        o_rs_entry_valid,
    input  wire [STRUCT_EX_CORES-1:0]                                                        i_rs_entry_get,
    output wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                          o_rs_entry_data,

    // EX Result Receive (EX Out)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                               i_wbc_result_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0]               i_wbc_result_data,
    // Branch EX must report the resolved next PC and the originating {Flow, PC}.
    input wire [STRUCT_EX_BRANCH-1:0] i_wbc_result_branch_valid,
    input wire [STRUCT_EX_BRANCH*_BITWIDTH_STRUCT_BRANCH_RESULT-1:0] i_wbc_result_branch_data,
    // Recovery control: tags must have been age-qualified by FCL.
    output wire [IS_INST_REGS*_BITWIDTH_STRUCT_PHYREGS-1:0] o_rename_snapshot,
    // External execution / MMU sideband. These are transfer pulses, not requests.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_sidefx_valid,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_sidefx_tag,
    input wire [STRUCT_EX_OUT_RESULT_SUM-1:0] i_exception_valid,
    input wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_exception_tag,
    // Faulting EX must report its allocated destination PHYREG for synthetic
    // PRM wakeup (zero if no destination), even when no WBC result is produced.
    input wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_STRUCT_PHYREGS-1:0] i_exception_phyreg,
    input wire [STRUCT_EX_OUT_RESULT_SUM*6-1:0] i_exception_cause,
    input wire [STRUCT_EX_OUT_RESULT_SUM*IS_INST_PC_BITWIDTH-1:0] i_exception_tval,
    input wire i_interrupt_pending,
    input wire [5:0] i_interrupt_cause,
    input wire [IS_INST_PC_BITWIDTH-1:0] i_trap_vector_pc,
    output wire o_trap_csr_request,
    output wire o_trap_interrupt,
    output wire o_backend_kill_valid, o_backend_kill_inclusive,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] o_backend_kill_tag,
    output wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] o_backend_oldest_flow,
    output wire [STRUCT_EX_OUT_RESULT_SUM-1:0] o_wbc_accept,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_trap_epc,o_trap_tval,
    output wire [5:0] o_trap_cause,
    input wire i_trap_csr_done,
    output wire o_sidefx_valid,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] o_sidefx_tag,
    output wire [($clog2(STRUCT_FLOW_PC_MAX_RANGE))-1:0] o_sidefx_slot,
    input wire i_sidefx_ready,i_sidefx_done,i_sidefx_error,
    input wire [5:0] i_sidefx_error_cause,
    input wire [IS_INST_PC_BITWIDTH-1:0] i_sidefx_error_tval,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_commit_fire,
    output wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] o_commit_flow,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_commit_base_pc,
    output wire o_redirect_valid,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_redirect_pc,
    // Optional custom prediction plugin response (1 query at a time).
    output wire o_predict_query_valid,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_predict_query_pc,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] o_predict_query_tag,
    input wire i_predict_query_ready,
    input wire i_predict_response_valid,
    input wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_predict_response_tag,
    input wire i_predict_response_taken,
    input wire [IS_INST_PC_BITWIDTH-1:0] i_predict_response_target,
    output wire o_predict_response_ready,
    output wire [STRUCT_EX_BRANCH-1:0] o_predict_update_valid,
    output wire [STRUCT_EX_BRANCH*_BITWIDTH_FLOW_WINDOWS_PC-1:0] o_predict_update_tag,
    output wire [STRUCT_EX_BRANCH*IS_INST_PC_BITWIDTH-1:0] o_predict_update_pc,
    output wire [STRUCT_EX_BRANCH-1:0] o_predict_update_taken,
    output wire [STRUCT_EX_BRANCH*IS_INST_PC_BITWIDTH-1:0] o_predict_update_target,
    // Optional external kill overrides for integration diagnostics; tie low
    // in a normal implementation. FCL-derived decisions are always enforced.
    input wire [STRUCT_EX_CORES-1:0] i_oryukdo_issue_kill,
    input wire [STRUCT_EX_OUT_RESULT_SUM-1:0] i_oryukdo_result_kill,
    output wire [STRUCT_EX_CORES-1:0] o_oryukdo_issue_discard,
    output wire [STRUCT_EX_OUT_RESULT_SUM-1:0] o_oryukdo_result_discard,
    output wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_STRUCT_EX_DONE_PC-1:0] o_oryukdo_result_discard_tag
);

    // Capture even a reset pulse between clock edges. Only this release chain
    // has asynchronous clear. Its final flop revokes transfers immediately.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [3:0] pin_release = '0;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) pin_release <= '0;
        else pin_release <= {pin_release[2:0], 1'b1};
    end

    // Synchronize both edges before reset can reach a RAM address or enable.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] core_release = '0;
    always_ff @(posedge clk) core_release <= {core_release[0], pin_release[1]};
    wire core_reset_n = core_release[1];
    // A single flop qualifies the interface even for a sub-cycle reset pulse.
    // Release aligns with core_release[1] on the fourth rising edge.
    // Only a stand-alone boundary may use asynchronous pin isolation. Inside
    // a CPU, Issue/Get/WBC paths feed back into the BRAM control cone.
    wire io_live = ASYNC_PORT_ISOLATION ? pin_release[3] : core_reset_n;

    // Keep asynchronous interface isolation outside the scheduler feedback.
    wire [STRUCT_DECODE_NEW_INST-1:0] core_im_req_pc_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0] core_im_recv_inst_get;
    wire [STRUCT_EX_CORES-1:0] core_rs_entry_valid;
    wire core_trap_csr_request;
    wire core_backend_kill_valid;
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] core_wbc_accept;
    wire core_sidefx_valid;
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] core_commit_fire;
    wire core_redirect_valid;
    wire core_predict_query_valid;
    wire core_predict_response_ready;
    wire [STRUCT_EX_BRANCH-1:0] core_predict_update_valid;
    wire [STRUCT_EX_CORES-1:0] core_oryukdo_issue_discard;
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] core_oryukdo_result_discard;

    assign o_im_req_pc_valid = io_live ? core_im_req_pc_valid : '0;
    assign o_im_recv_inst_get = io_live ? core_im_recv_inst_get : '0;
    assign o_rs_entry_valid = io_live ? core_rs_entry_valid : '0;
    assign o_trap_csr_request = io_live ? core_trap_csr_request : '0;
    assign o_backend_kill_valid = io_live ? core_backend_kill_valid : '0;
    assign o_wbc_accept = io_live ? core_wbc_accept : '0;
    assign o_sidefx_valid = io_live ? core_sidefx_valid : '0;
    assign o_commit_fire = io_live ? core_commit_fire : '0;
    assign o_redirect_valid = io_live ? core_redirect_valid : '0;
    assign o_predict_query_valid = io_live ? core_predict_query_valid : '0;
    assign o_predict_response_ready = io_live ? core_predict_response_ready : '0;
    assign o_predict_update_valid = io_live ? core_predict_update_valid : '0;
    assign o_oryukdo_issue_discard = io_live ? core_oryukdo_issue_discard : '0;
    assign o_oryukdo_result_discard = io_live ? core_oryukdo_result_discard : '0;



    wire                                                                                      nel_fcl_jumpbranch_valid;
    wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                              nel_fcl_jumpbranch_data;
    wire [STRUCT_EX_CORES*_BITWIDTH_EX_INST_WIDTH-1:0] guard_in_issue_data;
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] guard_out_result_valid;
    wire [STRUCT_EX_CORES-1:0] guard_in_issue_valid;
    localparam int SLOTS=STRUCT_FLOW_PC_MAX_RANGE;
    localparam int TAG_W=_BITWIDTH_FLOW_WINDOWS_PC;
    localparam int MAP_W=IS_INST_REGS*_BITWIDTH_STRUCT_PHYREGS;
    localparam int SLOT_W=(SLOTS>1?$clog2(SLOTS):1);
    wire [MAP_W-1:0] rename_snapshot;
    assign o_rename_snapshot=rename_snapshot;
    wire [TAG_W-1:0] branch_candidate_pc;
    wire branch_candidate_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0] nel_decode_exc_valid;
    wire [STRUCT_DECODE_NEW_INST*TAG_W-1:0] nel_decode_exc_tag;
    wire failed_response;
    wire [STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST:0] all_exception_valid =
        {failed_response,nel_decode_exc_valid,i_exception_valid};
    wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*TAG_W-1:0] all_exception_tag =
        {o_sidefx_tag,nel_decode_exc_tag,i_exception_tag};
    wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*6-1:0] all_exception_cause =
        {i_sidefx_error_cause,{STRUCT_DECODE_NEW_INST{6'd2}},i_exception_cause};
    wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*IS_INST_PC_BITWIDTH-1:0] all_exception_tval =
        {i_sidefx_error_tval,{(STRUCT_DECODE_NEW_INST*IS_INST_PC_BITWIDTH){1'b0}},i_exception_tval};
    wire [STRUCT_DECODE_NEW_INST-1:0] rename_rd_valid;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_IS_INST_REGS-1:0] rename_rd;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_STRUCT_PHYREGS-1:0] rename_phy;
    wire [STRUCT_DECODE_NEW_INST*TAG_W-1:0] rename_rd_tag;
    wire [SLOTS-1:0] oldest_admitted,oldest_done,oldest_discard,
        oldest_exception,oldest_sidefx,oldest_renamed;
    wire [SLOTS*6-1:0] oldest_cause;
    wire [SLOTS*IS_INST_PC_BITWIDTH-1:0] oldest_tval;
    wire [SLOTS*_BITWIDTH_IS_INST_REGS-1:0] oldest_rename_rd;
    wire [SLOTS*_BITWIDTH_STRUCT_PHYREGS-1:0] oldest_rename_phy;
    wire [MAP_W-1:0] oldest_baseline;
    wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] oldest_flow;
    wire oldest_open,oldest_closed,all_window_drained;
    wire fcl_fetch_drained,nel_stage2_drained;
    wire [IS_INST_PC_BITWIDTH-1:0] oldest_start_pc,oldest_next_pc;
    wire ctrl_kill_active,ctrl_kill_inclusive,ctrl_rename_stall,ctrl_redirect_valid;
    wire [TAG_W-1:0] ctrl_kill_boundary;
    wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] ctrl_kill_oldest;
    wire [IS_INST_PC_BITWIDTH-1:0] ctrl_redirect_pc;
    wire ctrl_map_write_valid,ctrl_map_write_ready;
    wire [_BITWIDTH_IS_INST_REGS-1:0] ctrl_map_write_logreg;
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0] ctrl_map_write_phyreg;
    wire ctrl_window_commit_done,all_branches_resolved,ctrl_recovery_busy;
    wire [1:0] ctrl_recovery_kind;
    wire reclaim_done;
    wire [SLOTS-1:0] oldest_killed;
    wire [STRUCT_EX_CORES-1:0] issue_auto_kill;
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] result_auto_kill;
    wire [STRUCT_EX_CORES*TAG_W-1:0] issue_candidate_tag;
    wire [STRUCT_EX_OUT_RESULT_SUM*TAG_W-1:0] result_candidate_tag;
    wire [STRUCT_EX_BRANCH-1:0] cp_result_valid=i_wbc_result_branch_valid;
    wire [STRUCT_EX_BRANCH*TAG_W-1:0] cp_result_tag;
    wire [STRUCT_EX_BRANCH*IS_INST_PC_BITWIDTH-1:0] cp_result_pc;
    wire [STRUCT_EX_BRANCH-1:0] cp_result_taken, branch_result_kill;
    wire [STRUCT_EX_BRANCH*IS_INST_PC_BITWIDTH-1:0] resolved_at_pc;
    oryukdo_recovery_boundary #(.FLOWS(STRUCT_FLOW_WINDOWS),.SLOT_W(IS_INST_PC_BITWIDTH),
        .WRAPPING_PC(1),.LANES(STRUCT_EX_BRANCH)) U_BRANCH_CLASSIFY (
        .i_recovery_active(ctrl_kill_active),.i_oldest_flow(ctrl_kill_oldest),
        .i_boundary_tag(ctrl_kill_boundary),.i_boundary_inclusive(ctrl_kill_inclusive),
        .i_candidate_valid(cp_result_valid),.i_candidate_tag(cp_result_tag),.o_kill(branch_result_kill));
    for(genvar bc=0;bc<STRUCT_EX_BRANCH;bc++) begin : G_CP_RESULT
        assign cp_result_tag[bc*TAG_W +: TAG_W] =
            i_wbc_result_branch_data[bc*_BITWIDTH_STRUCT_BRANCH_RESULT +: TAG_W];
        assign cp_result_pc[bc*IS_INST_PC_BITWIDTH +: IS_INST_PC_BITWIDTH] =
            i_wbc_result_branch_data[bc*_BITWIDTH_STRUCT_BRANCH_RESULT+TAG_W +: IS_INST_PC_BITWIDTH];
        assign resolved_at_pc[bc*IS_INST_PC_BITWIDTH +: IS_INST_PC_BITWIDTH] = cp_result_tag[bc*TAG_W +: IS_INST_PC_BITWIDTH];
        assign cp_result_taken[bc] = cp_result_pc[bc*IS_INST_PC_BITWIDTH +: IS_INST_PC_BITWIDTH] !=
            cp_result_tag[bc*TAG_W +: IS_INST_PC_BITWIDTH] + IS_INST_PC_BITWIDTH'(IS_INST_PC_STEP);
    end
    wire predictor_ready,predictor_valid,predictor_taken;
    wire [TAG_W-1:0] predictor_tag;
    wire [IS_INST_PC_BITWIDTH-1:0] predictor_next_pc;
    wire checkpoint_ready;
    wire predictor_result_matches= predictor_valid && predictor_tag==branch_candidate_pc;
    wire predictor_wait=branch_candidate_valid && !predictor_result_matches;
    wire effective_rename_stall=ctrl_rename_stall || predictor_wait;
    wire cp_push=nel_fcl_jumpbranch_valid &&
        (nel_fcl_jumpbranch_data[1] || nel_fcl_jumpbranch_data[2]);
    // Stable tagged query is issued once. A custom response is held until
    // the NEL control instruction is really renamed and checkpointed.
    logic prediction_requested;
    wire predictor_query_valid = branch_candidate_valid && !ctrl_recovery_busy &&
        (!USE_CUSTOM_BRANCH_PREDICTOR || !prediction_requested);
    wire drop_response = USE_CUSTOM_BRANCH_PREDICTOR && prediction_requested && ctrl_recovery_busy;
    wire response_consumed = cp_push || (drop_response && i_predict_response_valid);
    always_ff @(posedge clk) begin
        if (!core_reset_n) prediction_requested<=1'b0;
        else if (response_consumed)
            prediction_requested<=1'b0;
        else if (predictor_query_valid && predictor_ready)
            prediction_requested<=1'b1;
    end
    oryukdo_branch_predictor #(
        .PC_W(IS_INST_PC_BITWIDTH),.PC_STEP(IS_INST_PC_STEP),
        .TAG_W(TAG_W),.FETCH_WIDTH(1),.RESOLVE_WIDTH(STRUCT_EX_BRANCH),
        .USE_CUSTOM(USE_CUSTOM_BRANCH_PREDICTOR)
    ) U_BRANCH_PREDICTOR (
        .i_predict_valid(predictor_query_valid),
        .i_predict_pc(branch_candidate_pc[0 +: IS_INST_PC_BITWIDTH]),
        .i_predict_tag(branch_candidate_pc),.o_predict_ready(predictor_ready),
        .o_predict_valid(predictor_valid),.o_predict_tag(predictor_tag),
        .o_predict_taken(predictor_taken),.o_predict_target(predictor_next_pc),
        .o_custom_query_valid(core_predict_query_valid),.o_custom_query_pc(o_predict_query_pc),
        .o_custom_query_tag(o_predict_query_tag),.i_custom_query_ready(i_predict_query_ready),
        .o_custom_prediction_ready(core_predict_response_ready),
        .i_custom_prediction_valid(i_predict_response_valid),
        .i_custom_prediction_tag(i_predict_response_tag),
        .i_custom_prediction_taken(i_predict_response_taken),
        .i_custom_prediction_target(i_predict_response_target),
        .i_response_consume(cp_push || drop_response),
        .i_resolve_valid(cp_result_valid),.i_resolve_tag(cp_result_tag),
        .i_resolve_pc(resolved_at_pc),
        .i_resolve_taken(cp_result_taken),.i_resolve_target(cp_result_pc),
        .i_resolve_squashed(branch_result_kill),
        .o_custom_update_valid(core_predict_update_valid),
        .o_custom_update_tag(o_predict_update_tag),.o_custom_update_pc(o_predict_update_pc),
        .o_custom_update_taken(o_predict_update_taken),
        .o_custom_update_target(o_predict_update_target)
    );
    // Detect one pulse per distinct oldest-window allocation.
    logic previous_oldest_open;
    logic [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] previous_oldest_flow;
    always_ff @(posedge clk) begin
        if (!core_reset_n) begin previous_oldest_open<=1'b0;previous_oldest_flow<='0;end
        else begin previous_oldest_open<=oldest_open;
            previous_oldest_flow<=oldest_flow;end
    end
    wire oldest_window_begin=oldest_open &&
        (!previous_oldest_open || previous_oldest_flow!=oldest_flow);
    logic window_commit_held;
    logic irq_window_waiting;
    always_ff @(posedge clk) begin
        if (!core_reset_n) window_commit_held<=1'b0;
        else if (oldest_window_begin) window_commit_held<=1'b0;
        else if (ctrl_window_commit_done ||
            (ctrl_redirect_valid && ctrl_recovery_kind!=2'd0))
            window_commit_held<=1'b1;
    end
    always_ff @(posedge clk) begin
        if (!core_reset_n) irq_window_waiting<=1'b0;
        else if (ctrl_redirect_valid || oldest_window_begin) irq_window_waiting<=1'b0;
        else if (ctrl_window_commit_done && i_interrupt_pending && (|(oldest_admitted & ~oldest_killed))) irq_window_waiting<=1'b1;
    end
    wire fcl_retire_permitted=window_commit_held &&
        !ctrl_recovery_busy && !irq_window_waiting && !oldest_window_begin;
    logic [$clog2(SLOTS+1)-1:0] oldest_length;
    logic [SLOTS*IS_INST_PC_BITWIDTH-1:0] oldest_slot_pc;
    always_comb begin
        oldest_length='0;
        for(int si=0;si<SLOTS;si++) begin
            oldest_slot_pc[si*IS_INST_PC_BITWIDTH +: IS_INST_PC_BITWIDTH]=
                oldest_start_pc + IS_INST_PC_BITWIDTH'(si*IS_INST_PC_STEP);
            if(oldest_admitted[si]) oldest_length=$clog2(SLOTS+1)'(si+1);
        end
    end
    oryukdo_control_plane #(
        .PC_W(IS_INST_PC_BITWIDTH),.PC_STEP(IS_INST_PC_STEP),
        .RESOLVE_LANES(STRUCT_EX_BRANCH),.FLOWS(STRUCT_FLOW_WINDOWS),.SLOTS(SLOTS),.DECODE(STRUCT_DECODE_NEW_INST),
        .PHY_W(_BITWIDTH_STRUCT_PHYREGS),.LOGICAL_REGS(IS_INST_REGS)
    ) U_CONTROL_PLANE (
        .clk(clk),.reset_n(core_reset_n),
        .i_branch_candidate_valid(branch_candidate_valid),
        .i_checkpoint_valid(cp_push),.o_checkpoint_ready(checkpoint_ready),
        .i_checkpoint_tag(branch_candidate_pc),
        .i_predicted_next_pc(predictor_next_pc),.i_checkpoint_map(rename_snapshot),
        .i_branch_result_valid(cp_result_valid),.i_branch_result_tag(cp_result_tag),
        .i_branch_result_pc(cp_result_pc),
        .i_oldest_flow(oldest_flow),.i_window_open(oldest_window_begin),
        .i_window_closed(oldest_closed),.i_window_length(oldest_length),
        .i_slot_valid(oldest_admitted),.i_slot_done(oldest_done),
        .i_slot_squashed(oldest_killed),.i_slot_exception(oldest_exception),
        .i_slot_sidefx(oldest_sidefx),.i_slot_pc(oldest_slot_pc),
        .i_slot_tval(oldest_tval),.i_slot_cause(oldest_cause),
        .i_next_window_pc(oldest_next_pc),.i_oldest_start_pc(oldest_start_pc),
        .i_interrupt_pending(i_interrupt_pending),.i_interrupt_cause(i_interrupt_cause),
        .i_trap_vector_pc(i_trap_vector_pc),
        .i_drain_done(all_window_drained && reclaim_done &&
            fcl_fetch_drained && nel_stage2_drained && (!USE_CUSTOM_BRANCH_PREDICTOR || !prediction_requested)),
        .i_trap_baseline_map(oldest_baseline),.i_trap_renamed(oldest_renamed),
        .i_trap_rename_rd(oldest_rename_rd),.i_trap_rename_phy(oldest_rename_phy),
        .o_map_write_valid(ctrl_map_write_valid),.o_map_write_logreg(ctrl_map_write_logreg),
        .o_map_write_phyreg(ctrl_map_write_phyreg),.i_map_write_ready(1'b1),
        .o_failed_response(failed_response),.o_sidefx_valid(core_sidefx_valid),.o_sidefx_slot(o_sidefx_slot),
        .i_sidefx_ready(i_sidefx_ready),.i_sidefx_done(i_sidefx_done),
        .i_sidefx_error(i_sidefx_error),.i_sidefx_error_cause(i_sidefx_error_cause),
        .o_trap_csr_request(core_trap_csr_request),.o_trap_epc(o_trap_epc),
        .o_trap_tval(o_trap_tval),.o_trap_cause(o_trap_cause),.i_trap_csr_done(i_trap_csr_done),
        .o_kill_active(ctrl_kill_active),.o_kill_boundary_tag(ctrl_kill_boundary),
        .o_kill_inclusive(ctrl_kill_inclusive),.o_kill_oldest_flow(ctrl_kill_oldest),
        .o_rename_stall(ctrl_rename_stall),.o_redirect_valid(ctrl_redirect_valid),
        .o_redirect_pc(ctrl_redirect_pc),.o_commit_fire(core_commit_fire),
        .o_window_commit_done(ctrl_window_commit_done),
        .o_speculative_branches_empty(all_branches_resolved),
        .o_recovery_kind(ctrl_recovery_kind),.o_recovery_busy(ctrl_recovery_busy)
    );
    assign o_commit_flow=oldest_flow;
    assign o_commit_base_pc=oldest_start_pc;
    assign core_backend_kill_valid=ctrl_kill_active;
    assign o_backend_kill_inclusive=ctrl_kill_inclusive;
    assign o_backend_kill_tag=ctrl_kill_boundary;
    assign o_backend_oldest_flow=ctrl_kill_oldest;
    assign core_wbc_accept=guard_out_result_valid;
    assign o_trap_interrupt=(ctrl_recovery_kind==2'd2);
    assign core_redirect_valid=ctrl_redirect_valid;
    assign o_redirect_pc=ctrl_redirect_pc;
    assign o_sidefx_tag={oldest_flow,
        oldest_start_pc + IS_INST_PC_BITWIDTH'(o_sidefx_slot)*IS_INST_PC_BITWIDTH'(IS_INST_PC_STEP)};
    for(genvar ic=0;ic<STRUCT_EX_CORES;ic++) begin : G_ISSUE_CLASSIFY
        assign issue_candidate_tag[ic*TAG_W +: TAG_W]=
            guard_in_issue_data[ic*_BITWIDTH_EX_INST_WIDTH +: TAG_W];
    end
    for(genvar rc=0;rc<STRUCT_EX_OUT_RESULT_SUM;rc++) begin : G_RESULT_CLASSIFY
        assign result_candidate_tag[rc*TAG_W +: TAG_W]=
            i_wbc_result_data[rc*_BITWIDTH_EX_RESULT_WIDTH +: TAG_W];
    end
    oryukdo_recovery_boundary #(.FLOWS(STRUCT_FLOW_WINDOWS),
        .SLOT_W(IS_INST_PC_BITWIDTH),.WRAPPING_PC(1),.LANES(STRUCT_EX_CORES)) U_ISSUE_CLASSIFY (
        .i_recovery_active(ctrl_kill_active),.i_oldest_flow(ctrl_kill_oldest),
        .i_boundary_tag(ctrl_kill_boundary),.i_boundary_inclusive(ctrl_kill_inclusive),
        .i_candidate_valid(guard_in_issue_valid),.i_candidate_tag(issue_candidate_tag),
        .o_kill(issue_auto_kill)
    );
    oryukdo_recovery_boundary #(.FLOWS(STRUCT_FLOW_WINDOWS),
        .SLOT_W(IS_INST_PC_BITWIDTH),.WRAPPING_PC(1),.LANES(STRUCT_EX_OUT_RESULT_SUM)) U_RESULT_CLASSIFY (
        .i_recovery_active(ctrl_kill_active),.i_oldest_flow(ctrl_kill_oldest),
        .i_boundary_tag(ctrl_kill_boundary),.i_boundary_inclusive(ctrl_kill_inclusive),
        .i_candidate_valid(i_wbc_result_valid),.i_candidate_tag(result_candidate_tag),
        .o_kill(result_auto_kill)
    );

// START ===[ INTERNAL WIRE AREA ]=== START //
    // Boundary guards: only handshake-level filtering, no FIFO middle deletion.
    // All age comparisons and recovery classification must come from FCL.
    wire [STRUCT_EX_CORES-1:0] guard_in_issue_get;
    wire lsq_order_discard_valid,lsq_ready_discard_valid;
    wire lsq_cancel_phy_valid;
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0] lsq_cancel_phy;
    wire [TAG_W-1:0] lsq_order_discard_tag,lsq_ready_discard_tag;
    wire [STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+2-1:0] fdu_discard_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+2)*_BITWIDTH_STRUCT_EX_DONE_PC-1:0] fdu_discard_tag;
    assign fdu_discard_valid = {lsq_ready_discard_valid,lsq_order_discard_valid,
        core_oryukdo_issue_discard,core_oryukdo_result_discard};
    assign fdu_discard_tag[(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES)*TAG_W +: TAG_W]=
        lsq_order_discard_tag;
    assign fdu_discard_tag[(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+1)*TAG_W +: TAG_W]=
        lsq_ready_discard_tag;
    for(genvar d=0;d<STRUCT_EX_CORES;d++) begin : G_FDU_ISSUE_DISCARD
        assign fdu_discard_tag[(STRUCT_EX_OUT_RESULT_SUM+d)*_BITWIDTH_STRUCT_EX_DONE_PC +: _BITWIDTH_STRUCT_EX_DONE_PC] =
            guard_in_issue_data[d*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_STRUCT_EX_DONE_PC];
    end
    assign fdu_discard_tag[0 +: STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_STRUCT_EX_DONE_PC] =
        o_oryukdo_result_discard_tag;
    wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_EX_RESULT_WIDTH-1:0] guard_out_result_data;
    wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_EX_RESULT_WIDTH-1:0] result_guard_input_data = i_wbc_result_data;
    wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_STRUCT_EX_DONE_PC-1:0] result_guard_input_tag;
    for (genvar t=0; t<STRUCT_EX_OUT_RESULT_SUM; t++) begin : G_RESULT_TAG
        assign result_guard_input_tag[t*_BITWIDTH_STRUCT_EX_DONE_PC +: _BITWIDTH_STRUCT_EX_DONE_PC] =
            i_wbc_result_data[t*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_STRUCT_EX_DONE_PC];
    end
    oryukdo_issue_guard #(
        .LANES(STRUCT_EX_CORES), .DATA_W(_BITWIDTH_EX_INST_WIDTH)
    ) U_ORYUKDO_ISSUE_GUARD (
        .i_valid(guard_in_issue_valid), .o_get(guard_in_issue_get),
        .i_data(guard_in_issue_data), .i_kill(i_oryukdo_issue_kill | issue_auto_kill),
        .i_ex_get(i_rs_entry_get), .o_ex_valid(core_rs_entry_valid),
        .o_ex_data(o_rs_entry_data), .o_discard_fire(core_oryukdo_issue_discard)
    );
    oryukdo_result_guard #(
        .LANES(STRUCT_EX_OUT_RESULT_SUM), .DATA_W(_BITWIDTH_EX_RESULT_WIDTH),
        .TAG_W(_BITWIDTH_STRUCT_EX_DONE_PC)
    ) U_ORYUKDO_RESULT_GUARD (
        .i_valid(i_wbc_result_valid), .i_data(result_guard_input_data),
        .i_tag(result_guard_input_tag), .i_kill(i_oryukdo_result_kill | result_auto_kill),
        .o_wbc_valid(guard_out_result_valid), .o_wbc_data(guard_out_result_data),
        .o_discard_valid(core_oryukdo_result_discard),
        .o_discard_tag(o_oryukdo_result_discard_tag)
    );

    // IM -> NEL : Instruction Receive
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_inst_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_inst_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_FLOW_WINDOWS_PC) )-1:0]                         im_nel_recv_pc;

    // PRM -> NEL : Allocatable Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                          prm_nel_phyreg_data;

    // A killed result must still wake wrong-path dependents in IST/RS,
    // otherwise an unready younger instruction can block recovery forever.
    // These wakeups are ONLY dependency-drain events, not committed writes.
    wire [STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES+1:0] prm_wakeup_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES+2)*_BITWIDTH_STRUCT_PHYREGS-1:0] prm_wakeup_phy;
    localparam int BUS_WAKE=STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES+1;
    assign prm_wakeup_valid[BUS_WAKE]=failed_response && oldest_renamed[o_sidefx_slot];
    assign prm_wakeup_phy[BUS_WAKE*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS]=
        oldest_rename_phy[int'(o_sidefx_slot)*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS];
    for(genvar wake=0;wake<STRUCT_EX_OUT_RESULT_SUM;wake++) begin : G_RAW_EX_WAKE
        assign prm_wakeup_valid[wake]=i_wbc_result_valid[wake];
        assign prm_wakeup_phy[wake*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] =
            i_wbc_result_data[wake*_BITWIDTH_EX_RESULT_WIDTH+TAG_W +: _BITWIDTH_STRUCT_PHYREGS];
    end
    for(genvar wake=0;wake<STRUCT_EX_CORES;wake++) begin : G_SQUASH_EX_WAKE
        assign prm_wakeup_valid[STRUCT_EX_OUT_RESULT_SUM+wake]=core_oryukdo_issue_discard[wake];
        assign prm_wakeup_phy[(STRUCT_EX_OUT_RESULT_SUM+wake)*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] =
            guard_in_issue_data[wake*_BITWIDTH_EX_INST_WIDTH + TAG_W+
                _BITWIDTH_STRUCT_EX_PATH+EX_INST_MICROOP_BITWIDTH+IS_INST_IMM +: _BITWIDTH_STRUCT_PHYREGS];
    end
    for(genvar excwake=0;excwake<STRUCT_EX_OUT_RESULT_SUM;excwake++) begin : G_EXC_DEST_WAKE
        assign prm_wakeup_valid[STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+excwake]=
            i_exception_valid[excwake] &&
            (i_exception_phyreg[excwake*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] != '0);
        assign prm_wakeup_phy[(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+excwake)*_BITWIDTH_STRUCT_PHYREGS
            +: _BITWIDTH_STRUCT_PHYREGS]=
            i_exception_phyreg[excwake*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS];
    end
    assign prm_wakeup_valid[STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES] =
        lsq_cancel_phy_valid;
    assign prm_wakeup_phy[(STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES)*_BITWIDTH_STRUCT_PHYREGS
        +: _BITWIDTH_STRUCT_PHYREGS]=lsq_cancel_phy;
    // WBC -> NEL, PRM (Broadcast) : Done Physical Registers
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_broadcast_done_phyreg_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        wbc_broadcast_done_phyreg_data;

    // NEL -> IST : New Internal Instructions
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_INTERNAL_INST_WIDTH) )-1:0]                     nel_ist_new_inst_data;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         ist_nel_accept;
    wire                                                                                     lsq_order_ready;

    // NEL -> FCL : Retired Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_fcl_retired_phyreg_valid;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0]               nel_fcl_retired_phyreg_data;
    
    // NEL -> FCL : Jump/Branch Information

    // PRM -> IST : Ready Phyreg/ISTmap pair
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        prm_ist_ready_phyreg_valid;
    wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_READY_PRM) )-1:0]                              prm_ist_ready_phyreg_data;

    // IST -> RS : Executable (All phyreg in instruction are ready) Internal Instructions
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               ist_rs_ready_inst_valid;
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               ist_rs_ready_inst_get;
    wire [((STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] ist_rs_ready_inst_data;

    // IST -> PRM : Wait Phyreg/ISTmap pair
    wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                                      ist_prm_wait_phyreg_valid;
    wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM))-1:0]                ist_prm_wait_phyreg_data;

    // RS -> EX : Wait EX Instructions
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_valid;
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_get;
    wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                                  rs_ex_wait_inst_data;

    // EX -> WBC : Done EX Branch Result
    wire [STRUCT_EX_BRANCH-1:0]                                                               ex_wbc_result_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_BRANCH_RESULT) )-1:0]                       ex_wbc_result_branch_data;
    
    // EX -> WBC : Done EX Phyreg Result
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       ex_wbc_result_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0]                       ex_wbc_result_data;
    
    // WBC -> FCL : Branch Result
    wire [STRUCT_EX_BRANCH-1:0]                                                               wbc_fcl_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_BRANCH_RESULT) )-1:0]                       wbc_fcl_branch_data;
    
    // WBC -> FCL : Done PC
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_fcl_done_pc_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]                     wbc_fcl_done_pc_data;

    // FCL -> IM : New PC Request
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_get;
    wire [(STRUCT_DECODE_NEW_INST *_BITWIDTH_FLOW_WINDOWS_PC)-1:0]                             fcl_im_req_pc;

    // FCL -> PRM : Unallocate Retired Registers
    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                                       fcl_prm_unallocate_phyreg_valid;
    wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        fcl_prm_unallocate_phyreg_data;

    // DECODER -> NEL : ISA Infomation
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_exception;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                          dec_nel_decode_expath;
    wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                          dec_nel_decode_microop;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_IS_INST_REGS) )-1:0]                            dec_nel_decode_rd;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_newreg;
    wire [((STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS) *(_BITWIDTH_IS_INST_REGS) )-1:0]         dec_nel_decode_rs;
    wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                                       dec_nel_decode_imm;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump_reg;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_branch;

    wire fcl_nel_discard, nel_fcl_recv_control;
    wire [STRUCT_DECODE_NEW_INST-1:0] nel_fcl_recv_valid, nel_fcl_recv_keep, nel_fcl_new_inst_valid;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] nel_fcl_new_inst_pc;
    wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] nel_fcl_jumpbranch_pc;

// END   ===[ INTERNAL WIRE AREA ]===   END //

// START ===[ INSTANCE AREA ]=== START //
    oryukdo_new_entry_logic #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_NEW_ENTRY_LOGIC (
        .i_recovery_stall(effective_rename_stall),
        .i_recovery_flush(ctrl_redirect_valid),
        .o_renamed_stage_drained(nel_stage2_drained),
        .i_restore_valid(ctrl_map_write_valid),
        .i_restore_logreg(ctrl_map_write_logreg),
        .i_restore_phyreg(ctrl_map_write_phyreg),
        .o_rename_snapshot(rename_snapshot),
        .o_branch_candidate_pc(branch_candidate_pc),
        .o_branch_candidate_valid(branch_candidate_valid),
        .o_decode_exception_valid(nel_decode_exc_valid),
        .o_decode_exception_tag(nel_decode_exc_tag),
        .o_rename_rd_valid(rename_rd_valid),
        .o_rename_rd(rename_rd),.o_rename_phy(rename_phy),
        .o_rename_tag(rename_rd_tag),
        .clk                            (clk),
        .reset_n                        (core_reset_n),

        // Instruction Input (IM)
        .i_im_recv_inst_valid           (im_nel_recv_inst_valid),
        .o_im_recv_inst_get             (im_nel_recv_inst_get),
        .i_im_recv_pc                   (im_nel_recv_pc),
        .i_fcl_discard                  (fcl_nel_discard || ctrl_kill_active || ctrl_redirect_valid),
        .o_fcl_recv_valid               (nel_fcl_recv_valid),
        .o_fcl_recv_keep                (nel_fcl_recv_keep),
        .o_fcl_recv_control             (nel_fcl_recv_control),
        .o_fcl_new_inst_valid           (nel_fcl_new_inst_valid),
        .o_fcl_new_inst_pc              (nel_fcl_new_inst_pc),

        // Allocate Physical Registers Input (PRM)
        .i_prm_phyreg_valid             (prm_nel_phyreg_valid),
        .o_prm_phyreg_get               (prm_nel_phyreg_get),
        .i_prm_phyreg_data              (prm_nel_phyreg_data),

        // Done Physical Registers Input (WBC)
        .i_wbc_done_phyreg_valid        (wbc_broadcast_done_phyreg_valid),
        .i_wbc_done_phyreg_data         (wbc_broadcast_done_phyreg_data),

        // Decoder Input (Decoder)
        .i_dec_decode_exception         (dec_nel_decode_exception),
        .i_dec_decode_expath            (dec_nel_decode_expath),
        .i_dec_decode_microop           (dec_nel_decode_microop),
        .i_dec_decode_rd                (dec_nel_decode_rd),
        .i_dec_decode_newreg            (dec_nel_decode_newreg),
        .i_dec_decode_rs                (dec_nel_decode_rs),
        .i_dec_decode_imm               (dec_nel_decode_imm),
        .i_dec_decode_jump              (dec_nel_decode_jump),
        .i_dec_decode_jump_reg          (dec_nel_decode_jump_reg),
        .i_dec_decode_branch            (dec_nel_decode_branch),

        // Create Internal Instruction Output (IST)
        .o_ist_new_inst_valid           (nel_ist_new_inst_valid),
        .i_ist_new_inst_get             (nel_ist_new_inst_get),
        .o_ist_new_inst_data            (nel_ist_new_inst_data),

        // Retired Physical Registers Output (FCL)
        .o_fcl_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .o_fcl_retired_phyreg_data      (nel_fcl_retired_phyreg_data),

        // Jump/Branch Information Output (FCL)
        .o_fcl_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .o_fcl_jumpbranch_data          (nel_fcl_jumpbranch_data),
        .o_fcl_jumpbranch_pc            (nel_fcl_jumpbranch_pc)
    );

    instruction_state_table #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_IST_ISSUE_WIDTH(STRUCT_IST_ISSUE_WIDTH),
        .STRUCT_IST_BANKS(STRUCT_IST_BANKS),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_INSTRUCTION_STATE_TABLE (
        .clk                            (clk),
        .reset_n                        (core_reset_n),

        // New Internal Instruction Input (NEL)
        .i_nel_new_inst_valid           (nel_ist_new_inst_valid),
        .o_nel_new_inst_get             (ist_nel_accept),
        .i_nel_new_inst_data            (nel_ist_new_inst_data),

        // Ready Physical Registers Input (PRM)
        .i_prm_ready_phyreg_valid       (prm_ist_ready_phyreg_valid), 
        .i_prm_ready_phyreg_data        (prm_ist_ready_phyreg_data), 
        
        // Executable (All phyreg in instruction are ready) Internal Instruction Output (RS)
        .o_rs_ready_inst_valid          (ist_rs_ready_inst_valid),
        .i_rs_ready_inst_get            (ist_rs_ready_inst_get),
        .o_rs_ready_inst_data           (ist_rs_ready_inst_data),

        // Wait Physical Registers Output (PRM)
        .o_prm_wait_phyreg_valid        (ist_prm_wait_phyreg_valid),
        .o_prm_wait_phyreg_data         (ist_prm_wait_phyreg_data)
    );

    ready_station #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_RS_FIFO_WIDTH(STRUCT_RS_FIFO_WIDTH),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_IST_ISSUE_WIDTH(STRUCT_IST_ISSUE_WIDTH),
        .STRUCT_IST_BANKS(STRUCT_IST_BANKS),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_READY_STATION (
        .clk                            (clk),
        .reset_n                        (core_reset_n),

        // Executable (All phyreg in instruction are ready) Internal Instruction Input (IST)
        .i_ist_ready_inst_valid         (ist_rs_ready_inst_valid),
        .o_ist_ready_inst_get           (ist_rs_ready_inst_get),
        .i_ist_ready_inst_data          (ist_rs_ready_inst_data),

        // Wait EX Instruction Output (EX)
        .o_ex_wait_inst_valid           (rs_ex_wait_inst_valid),
        .i_ex_wait_inst_get             (rs_ex_wait_inst_get),
        .o_ex_wait_inst_data            (rs_ex_wait_inst_data)
    );

    write_back_concatenation #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_WRITE_BACK_CONCATENATION (
        // Result branch EX Input (EX)
        .i_ex_result_branch_valid       (ex_wbc_result_branch_valid),
        .i_ex_result_branch_data        (ex_wbc_result_branch_data),

        // Result EX Input (EX)
        .i_ex_result_valid              (ex_wbc_result_valid),
        .i_ex_result_data               (ex_wbc_result_data),

        // Branch Result Output (FCL)
        .o_fcl_branch_valid             (wbc_fcl_branch_valid),
        .o_fcl_branch_data              (wbc_fcl_branch_data),

        // Done PC Output (FCL)
        .o_fcl_done_pc_valid            (wbc_fcl_done_pc_valid),
        .o_fcl_done_pc_data             (wbc_fcl_done_pc_data),

        // Broadcast Done phyreg Output (NEL, PRM)
        .o_broadcast_done_phyreg_valid  (wbc_broadcast_done_phyreg_valid),
        .o_broadcast_done_phyreg_data   (wbc_broadcast_done_phyreg_data)
    );

    oryukdo_flow_control_logic #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_FLOW_CONTROL_LOGIC (
        .i_nel_predict_target(predictor_next_pc),
        .i_recovery_stall(effective_rename_stall),
        .i_recovery_redirect_valid(ctrl_redirect_valid),
        .i_recovery_redirect_pc(ctrl_redirect_pc),
        .i_retire_permitted(fcl_retire_permitted),
        .i_recovery_kill_active(ctrl_kill_active),
        .i_recovery_kill_inclusive(ctrl_kill_inclusive),
        .i_recovery_oldest_flow(ctrl_kill_oldest),
        .i_recovery_kill_boundary(ctrl_kill_boundary),.o_reclaim_done(reclaim_done),
        .o_all_window_drained(all_window_drained),
        .o_fetch_responses_drained(fcl_fetch_drained),
        .o_oldest_flow(oldest_flow),.o_oldest_open(oldest_open),
        .o_oldest_closed(oldest_closed),.o_oldest_admitted(oldest_admitted),
        .o_oldest_completed(oldest_done),.o_oldest_discarded(oldest_discard),
        .o_oldest_killed(oldest_killed),
        .o_oldest_start_pc(oldest_start_pc),.o_oldest_next_pc(oldest_next_pc),
        .o_oldest_exception(oldest_exception),.o_oldest_sidefx(oldest_sidefx),
        .o_oldest_cause(oldest_cause),.o_oldest_tval(oldest_tval),
        .i_rename_current_map(rename_snapshot),.i_rename_rd_valid(rename_rd_valid),
        .i_rename_rd_tag(rename_rd_tag),.i_rename_rd(rename_rd),.i_rename_phy(rename_phy),
        .o_oldest_baseline_map(oldest_baseline),.o_oldest_renamed(oldest_renamed),
        .o_oldest_rename_rd(oldest_rename_rd),.o_oldest_rename_phy(oldest_rename_phy),
        .i_sidefx_valid(i_sidefx_valid),.i_sidefx_tag(i_sidefx_tag),
        .i_exception_valid(all_exception_valid),.i_exception_tag(all_exception_tag),
        .i_exception_cause(all_exception_cause),.i_exception_tval(all_exception_tval),
        .i_squash_done_valid(fdu_discard_valid),
        .i_squash_done_pc(fdu_discard_tag),
        .clk                            (clk),
        .reset_n                        (core_reset_n),
        
        // Done PC Input (WBC)
        .i_wbc_done_pc_valid            (wbc_fcl_done_pc_valid),
        .i_wbc_done_pc_data             (wbc_fcl_done_pc_data),
        
        // Jump/Branch Information Input (NEL)
        .i_nel_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .i_nel_jumpbranch_data          (nel_fcl_jumpbranch_data),
        .i_nel_jumpbranch_pc            (nel_fcl_jumpbranch_pc),
        .i_nel_recv_valid               (nel_fcl_recv_valid),
        .i_nel_recv_keep                (nel_fcl_recv_keep),
        .i_nel_recv_control             (nel_fcl_recv_control),
        .o_nel_discard                  (fcl_nel_discard),
        .i_nel_new_inst_valid           (nel_fcl_new_inst_valid),
        .i_nel_new_inst_pc              (nel_fcl_new_inst_pc),
        .i_wbc_branch_valid             (wbc_fcl_branch_valid),
        .i_wbc_branch_data              (wbc_fcl_branch_data),

        // Retired Physical Registers Input (NEL)
        .i_nel_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .i_nel_retired_phyreg_data      (nel_fcl_retired_phyreg_data),

        // Request New Instruction Output (IM)
        .o_im_req_pc_valid              (fcl_im_req_pc_valid),
        .i_im_req_pc_get                (fcl_im_req_pc_get),
        .o_im_req_pc                    (fcl_im_req_pc),

        // Unallocate Retired Registers Output (PRM)
        .o_prm_unallocate_phyreg_valid  (fcl_prm_unallocate_phyreg_valid),
        .o_prm_unallocate_phyreg_data   (fcl_prm_unallocate_phyreg_data)
    );

    physical_register_mapper #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM*2+STRUCT_EX_CORES+2),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_PHYSICAL_REGISTER_MAPPER (
        .clk                            (clk),
        .reset_n                        (core_reset_n),

        // Wait Physical Registers Input (IST)
        .i_ist_wait_phyreg_valid        (ist_prm_wait_phyreg_valid),
        .i_ist_wait_phyreg_data         (ist_prm_wait_phyreg_data),
        
        // Broadcast Done phyreg Input (WBC)
        .i_wbc_done_phyreg_valid        (prm_wakeup_valid),
        .i_wbc_done_phyreg_data         (prm_wakeup_phy),

        // Unallocate Retired Registers Input (FCL)
        .i_fcl_unallocate_phyreg_valid  (fcl_prm_unallocate_phyreg_valid),
        .i_fcl_unallocate_phyreg_data   (fcl_prm_unallocate_phyreg_data),

        // Allocate Physical Registers Output (NEL)
        .o_nel_phyreg_valid             (prm_nel_phyreg_valid),
        .i_nel_phyreg_get               (prm_nel_phyreg_get),
        .o_nel_phyreg_data              (prm_nel_phyreg_data),

        // Ready Physical Registers Output (IST)
        .o_ist_ready_phyreg_valid       (prm_ist_ready_phyreg_valid), 
        .o_ist_ready_phyreg_data        (prm_ist_ready_phyreg_data)
    );

// END   ===[ INSTANCE AREA ]===   END //

// START ===[ INPUT, OUTPUT AREA ]=== START //
    // PC Request Output
    assign core_im_req_pc_valid          = fcl_im_req_pc_valid;
    assign fcl_im_req_pc_get          = i_im_req_pc_get;
    assign o_im_req_pc                = fcl_im_req_pc;

    // Instruction Receive Input
    assign im_nel_recv_inst_valid     = i_im_recv_inst_valid;
    assign core_im_recv_inst_get         = im_nel_recv_inst_get;
    assign im_nel_recv_pc             = i_im_recv_pc;

    // Decoder Info Receive
    assign dec_nel_decode_exception   = i_nel_decode_exception;
    assign dec_nel_decode_expath      = i_nel_decode_expath;
    assign dec_nel_decode_microop     = i_nel_decode_microop;
    assign dec_nel_decode_rd          = i_nel_decode_rd;
    assign dec_nel_decode_newreg      = i_nel_decode_newreg;
    assign dec_nel_decode_rs          = i_nel_decode_rs;
    assign dec_nel_decode_imm         = i_nel_decode_imm;
    assign dec_nel_decode_jump        = i_nel_decode_jump;
    assign dec_nel_decode_jump_reg    = i_nel_decode_jump_reg;
    assign dec_nel_decode_branch      = i_nel_decode_branch;

    // NEL valid is a transfer pulse, generated only when ALL get bits are high.
    // Reserve a whole decode bundle without feeding that pulse back into ready.
    assign nel_ist_new_inst_get = ist_nel_accept & {STRUCT_DECODE_NEW_INST{lsq_order_ready}};

    function automatic int lsq_ex_offset(input int path_index);
        int offset = 0;
        for (int p = 0; p < path_index; p++) offset += STRUCT_RS_OUT_ENTRY[p];
        return offset;
    endfunction

    generate
        if (ENABLE_LSQ) begin : G_LSQ
            localparam int FIRST = lsq_ex_offset(STRUCT_LSQ_EX_PATH);
            localparam int LANES = STRUCT_RS_OUT_ENTRY[STRUCT_LSQ_EX_PATH];
            wire [STRUCT_DECODE_NEW_INST-1:0] order_valid;
            wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] order_tag;
            for (genvar d = 0; d < STRUCT_DECODE_NEW_INST; d++) begin : G_ORDER
                assign order_valid[d] = nel_ist_new_inst_valid[d] && ist_nel_accept[d] &&
                    (nel_ist_new_inst_data[d*_BITWIDTH_INTERNAL_INST_WIDTH+_BITWIDTH_FLOW_WINDOWS_PC
                        +: _BITWIDTH_STRUCT_EX_PATH] == _BITWIDTH_STRUCT_EX_PATH'(STRUCT_LSQ_EX_PATH));
                assign order_tag[d*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                    nel_ist_new_inst_data[d*_BITWIDTH_INTERNAL_INST_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
            end
            // Critical correctness fix: a killed EX result is invisible to WBC,
            // but the LSQ still needs its raw completion. An issue-killed LSQ
            // head also needs a synthetic completion in that same handshake.
            // These events release LSQ ordering only. FDU reclaim remains
            // separately gated by the recovery controller's drain protocol.
            wire [2*STRUCT_EX_OUT_RESULT_SUM+LANES:0] lsq_done_valid;
            wire [(2*STRUCT_EX_OUT_RESULT_SUM+LANES+1)*_BITWIDTH_FLOW_WINDOWS_PC-1:0] lsq_done_tag;
            assign lsq_done_valid[2*STRUCT_EX_OUT_RESULT_SUM+LANES]=failed_response;
            assign lsq_done_tag[(2*STRUCT_EX_OUT_RESULT_SUM+LANES)*TAG_W +: TAG_W]=o_sidefx_tag;
            for (genvar dc=0; dc<STRUCT_EX_OUT_RESULT_SUM; dc++) begin : G_RAW_MEM_DONE
                assign lsq_done_valid[dc+STRUCT_EX_OUT_RESULT_SUM+LANES] = i_exception_valid[dc];
                assign lsq_done_tag[(dc+STRUCT_EX_OUT_RESULT_SUM+LANES)*TAG_W +: TAG_W] = i_exception_tag[dc*TAG_W +: TAG_W];
                assign lsq_done_valid[dc] = i_wbc_result_valid[dc];
                assign lsq_done_tag[dc*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                    i_wbc_result_data[dc*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
            end
            for (genvar dc=0; dc<LANES; dc++) begin : G_ISSUE_KILL_DONE
                assign lsq_done_valid[STRUCT_EX_OUT_RESULT_SUM+dc] =
                    core_oryukdo_issue_discard[FIRST+dc];
                assign lsq_done_tag[(STRUCT_EX_OUT_RESULT_SUM+dc)*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                    guard_in_issue_data[(FIRST+dc)*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
            end
            oryukdo_load_store_queue #(
                .TAG_WIDTH(_BITWIDTH_FLOW_WINDOWS_PC), .PC_WIDTH(IS_INST_PC_BITWIDTH),
                .FLOW_WINDOWS(STRUCT_FLOW_WINDOWS), .INST_WIDTH(_BITWIDTH_EX_INST_WIDTH),
                .EX_PATH_W(_BITWIDTH_STRUCT_EX_PATH),.MICROOP_W(EX_INST_MICROOP_BITWIDTH),
                .IMM_W(IS_INST_IMM),.PHY_W(_BITWIDTH_STRUCT_PHYREGS),
                .ORDER_CHANNELS(STRUCT_DECODE_NEW_INST), .READY_CHANNELS(LANES),
                .DONE_CHANNELS(2*STRUCT_EX_OUT_RESULT_SUM+LANES+1), .DEPTH(STRUCT_LSQ_ENTRIES)
            ) U_LSQ (
                .clk(clk), .reset_n(core_reset_n),
                .i_kill_active(ctrl_kill_active),.i_kill_inclusive(ctrl_kill_inclusive),
                .i_oldest_flow(ctrl_kill_oldest),.i_kill_boundary_tag(ctrl_kill_boundary),
                .i_order_head_kill(1'b0),.i_ready_head_kill(1'b0),
                .o_order_discard_valid(lsq_order_discard_valid),
                .o_order_discard_tag(lsq_order_discard_tag),
                .o_cancel_phy_valid(lsq_cancel_phy_valid),.o_cancel_phy(lsq_cancel_phy),
                .o_ready_discard_valid(lsq_ready_discard_valid),
                .o_ready_discard_tag(lsq_ready_discard_tag),
                .i_order_valid(order_valid), .i_order_tag(order_tag), .o_order_ready(lsq_order_ready),
                .i_ready_valid(rs_ex_wait_inst_valid[FIRST +: LANES]),
                .o_ready_get(rs_ex_wait_inst_get[FIRST +: LANES]),
                .i_ready_data(rs_ex_wait_inst_data[FIRST*_BITWIDTH_EX_INST_WIDTH +: LANES*_BITWIDTH_EX_INST_WIDTH]),
                .o_ex_valid(guard_in_issue_valid[FIRST +: LANES]), .i_ex_get(guard_in_issue_get[FIRST +: LANES]),
                .o_ex_data(guard_in_issue_data[FIRST*_BITWIDTH_EX_INST_WIDTH +: LANES*_BITWIDTH_EX_INST_WIDTH]),
                .i_done_valid(lsq_done_valid), .i_done_tag(lsq_done_tag)
            );
            for (genvar e = 0; e < STRUCT_EX_CORES; e++) begin : G_BYPASS_OTHER_PATHS
                if (e < FIRST || e >= FIRST+LANES) begin
                    assign guard_in_issue_valid[e] = rs_ex_wait_inst_valid[e];
                    assign rs_ex_wait_inst_get[e] = guard_in_issue_get[e];
                    assign guard_in_issue_data[e*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] =
                        rs_ex_wait_inst_data[e*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
                end
            end
            initial begin
                if (STRUCT_LSQ_EX_PATH < 0 || STRUCT_LSQ_EX_PATH >= STRUCT_EX_PATH || LANES < 1)
                    $fatal(1, "LSQ requires a valid EX path with at least one output");
            end
        end else begin : G_NO_LSQ
            assign lsq_order_ready = 1'b1;
            assign lsq_order_discard_valid=1'b0;assign lsq_ready_discard_valid=1'b0;
            assign lsq_order_discard_tag='0;assign lsq_ready_discard_tag='0;
            assign lsq_cancel_phy_valid=1'b0;assign lsq_cancel_phy='0;
            assign guard_in_issue_valid = rs_ex_wait_inst_valid;
            assign rs_ex_wait_inst_get = guard_in_issue_get;
            assign guard_in_issue_data = rs_ex_wait_inst_data;
        end
    endgenerate

    // EX Result Receive (EX Out)
    assign ex_wbc_result_valid        = guard_out_result_valid;
    assign ex_wbc_result_data         = guard_out_result_data;
    assign ex_wbc_result_branch_valid = i_wbc_result_branch_valid;
    assign ex_wbc_result_branch_data  = i_wbc_result_branch_data;

// END   ===[ INPUT, OUTPUT AREA ]===   END //

endmodule
