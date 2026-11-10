`timescale 1ns/1ps
module oryukdo_flow_control_logic #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 2,
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
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  wire                                                                        clk,
    input  wire                                                                        reset_n,
        
    // Ordered recovery boundary. Fetch is stopped during drain/rename replay.
    // Side-effect classification emitted only when NEL actually admits slot.
    input wire [IS_INST_REGS*_BITWIDTH_STRUCT_PHYREGS-1:0] i_rename_current_map,
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_rename_rd_valid,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_rename_rd_tag,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_IS_INST_REGS-1:0] i_rename_rd,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_STRUCT_PHYREGS-1:0] i_rename_phy,
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_sidefx_valid,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_sidefx_tag,
    // Exception is a terminal EX response, tagged by the existing Flow+PC.
    input wire [STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST:0] i_exception_valid,
    input wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_exception_tag,
    input wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*6-1:0] i_exception_cause,
    input wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1)*IS_INST_PC_BITWIDTH-1:0] i_exception_tval,
    input wire i_recovery_kill_active,
    input wire i_recovery_kill_inclusive,
    input wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] i_recovery_oldest_flow,
    input wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_recovery_kill_boundary,
    output wire o_reclaim_done,
    input wire i_retire_permitted,
    output wire o_all_window_drained,
    output wire o_fetch_responses_drained,
    input wire [IS_INST_PC_BITWIDTH-1:0] i_nel_predict_target,
    input wire i_recovery_stall,
    input wire i_recovery_redirect_valid,
    input wire [IS_INST_PC_BITWIDTH-1:0] i_recovery_redirect_pc,
    // Export original FDU bookkeeping for the oldest-window commit engine.
    output wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] o_oldest_flow,
    output wire o_oldest_open, o_oldest_closed,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_admitted,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_completed,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_discarded,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_killed,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_oldest_start_pc,
    output wire [IS_INST_PC_BITWIDTH-1:0] o_oldest_next_pc,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_exception,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_sidefx,
    output wire [IS_INST_REGS*_BITWIDTH_STRUCT_PHYREGS-1:0] o_oldest_baseline_map,
    output wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] o_oldest_renamed,
    output wire [STRUCT_FLOW_PC_MAX_RANGE*_BITWIDTH_IS_INST_REGS-1:0] o_oldest_rename_rd,
    output wire [STRUCT_FLOW_PC_MAX_RANGE*_BITWIDTH_STRUCT_PHYREGS-1:0] o_oldest_rename_phy,
    output wire [STRUCT_FLOW_PC_MAX_RANGE*6-1:0] o_oldest_cause,
    output wire [STRUCT_FLOW_PC_MAX_RANGE*IS_INST_PC_BITWIDTH-1:0] o_oldest_tval,
    // NEL input-response accounting. IM responses must remain in program order.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_recv_valid,
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_recv_keep,
    input wire i_nel_recv_control,
    output wire o_nel_discard,
    // All renamed instructions, including no-RD and x0 instructions.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_new_inst_valid,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_nel_new_inst_pc,
    // Resolved branch/jump-register result: {next_pc, flow, instruction_pc}.
    // EX supplies the actual next PC for both taken and not-taken branches.
    input wire [STRUCT_EX_BRANCH-1:0] i_wbc_branch_valid,
    input wire [STRUCT_EX_BRANCH*(IS_INST_PC_BITWIDTH+_BITWIDTH_FLOW_WINDOWS_PC)-1:0] i_wbc_branch_data,

    // Acknowledged disposal from issue/result/LSQ boundary guards.
    // A discard pulse is terminal for its associated instruction, and MUST
    // only be sent after an issued operation has no unreported future result.
    input wire [STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+2-1:0] i_squash_done_valid,
    input wire [(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+2)*_BITWIDTH_STRUCT_EX_DONE_PC-1:0] i_squash_done_pc,

    // Done PC Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                         i_wbc_done_pc_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]       i_wbc_done_pc_data,
        
    // Jump/Branch Information Input (NEL)
    input  wire                                                                        i_nel_jumpbranch_valid,
    input  wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                i_nel_jumpbranch_data,

    input wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_nel_jumpbranch_pc,

    // Retired Physical Registers Input (NEL)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_nel_retired_phyreg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0] i_nel_retired_phyreg_data,

    // Request New Instruction Output (IM)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                           o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST *_BITWIDTH_FLOW_WINDOWS_PC)-1:0]                 o_im_req_pc,

    // Unallocate Retired Registers Output (PRM)
    output wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                         o_prm_unallocate_phyreg_valid,
    output wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          o_prm_unallocate_phyreg_data
);

    localparam int FLOW_W = _BITWIDTH_STRUCT_FLOW_WINDOWS;
    localparam int PC_W = IS_INST_PC_BITWIDTH;
    localparam int TAG_W = _BITWIDTH_FLOW_WINDOWS_PC;
    localparam int BATCH_W = (STRUCT_DECODE_NEW_INST > 1)? $clog2(STRUCT_DECODE_NEW_INST+1) : 1;
    localparam int USED_W = (STRUCT_FLOW_PC_MAX_RANGE > 1)? $clog2(STRUCT_FLOW_PC_MAX_RANGE+1) : 1;

    logic [FLOW_W-1:0] head, head_next, tail, tail_next;
    logic current_valid, current_valid_next;
    logic [FLOW_W-1:0] current_flow, current_flow_next;
    logic [USED_W-1:0] current_used, current_used_next;
    logic [PC_W-1:0] next_pc, next_pc_next;

    // One in-order fetch bundle at a time. Later bundles can pass an unresolved branch.
    logic batch_active, batch_active_next, batch_discard, batch_discard_next;
    logic batch_control, batch_control_next;
    logic [STRUCT_DECODE_NEW_INST-1:0] request_pending, request_pending_next;
    logic [PC_W-1:0] batch_pc, batch_pc_next;
    logic [FLOW_W-1:0] batch_flow, batch_flow_next;
    logic [BATCH_W-1:0] batch_size, batch_size_next;
    logic [BATCH_W-1:0] received, received_next, kept, kept_next, renamed, renamed_next;

    logic [STRUCT_FLOW_WINDOWS-1:0] fdu_open, fdu_close;
    wire [STRUCT_FLOW_WINDOWS-1:0] branch_drained;
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_admitted [STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_completed [STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_discarded [STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_killed [STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_WINDOWS-1:0] fdu_closed;
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_exception[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_sidefx[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE*6-1:0] fdu_cause[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE*IS_INST_PC_BITWIDTH-1:0] fdu_tval[STRUCT_FLOW_WINDOWS];
    wire [IS_INST_PC_BITWIDTH-1:0] fdu_next[STRUCT_FLOW_WINDOWS];
    wire [IS_INST_REGS*_BITWIDTH_STRUCT_PHYREGS-1:0] fdu_baseline[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] fdu_renamed[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE*_BITWIDTH_IS_INST_REGS-1:0] fdu_rd[STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_PC_MAX_RANGE*_BITWIDTH_STRUCT_PHYREGS-1:0] fdu_phy[STRUCT_FLOW_WINDOWS];
    wire [IS_INST_PC_BITWIDTH-1:0] fdu_start [STRUCT_FLOW_WINDOWS];
    wire [STRUCT_FLOW_WINDOWS-1:0] fdu_active, fdu_release;
    logic windows_drained;
    always_comb begin
        windows_drained = 1'b1;
        for (int w=0;w<STRUCT_FLOW_WINDOWS;w++)
            if (fdu_active[w] && (!branch_drained[w] || (|(fdu_killed[w] & fdu_admitted[w] & ~(fdu_completed[w] | fdu_discarded[w])))))
                windows_drained = 1'b0;
    end
    // Already-sent PC requests must receive and discard their responses
    // before a Flow Window identifier is allowed to be reused.
    assign o_fetch_responses_drained =
        !(|request_pending) && (!batch_active || received==batch_size);
    assign o_all_window_drained = windows_drained;
    assign o_oldest_flow=head;
    assign o_oldest_open=fdu_active[head];
    assign o_oldest_closed=fdu_closed[head];
    assign o_oldest_admitted=fdu_admitted[head];
    assign o_oldest_completed=fdu_completed[head];
    assign o_oldest_discarded=fdu_discarded[head];
    assign o_oldest_killed=fdu_killed[head];
    assign o_oldest_start_pc=fdu_start[head];
    assign o_oldest_next_pc=fdu_next[head];
    assign o_oldest_exception=fdu_exception[head];
    assign o_oldest_sidefx=fdu_sidefx[head];
    assign o_oldest_baseline_map=fdu_baseline[head];
    assign o_oldest_renamed=fdu_renamed[head];
    assign o_oldest_rename_rd=fdu_rd[head];
    assign o_oldest_rename_phy=fdu_phy[head];
    assign o_oldest_cause=fdu_cause[head];
    assign o_oldest_tval=fdu_tval[head];
    wire [STRUCT_UNALLOCATE_PHYREG-1:0] fdu_retire_valid [0:STRUCT_FLOW_WINDOWS-1];
    wire [STRUCT_UNALLOCATE_PHYREG*_BITWIDTH_STRUCT_PHYREGS-1:0] fdu_retire_data [0:STRUCT_FLOW_WINDOWS-1];
    integer recv_sum, keep_sum, rename_sum, used_sum, request_size;
    integer lane;

    assign o_im_req_pc_valid = request_pending & {STRUCT_DECODE_NEW_INST{reset_n}};
    assign o_nel_discard = (batch_discard || i_recovery_kill_active) && reset_n;
    // Reclaim only NEW destinations of killed instructions. Old mapping
    // destinations are retained by the tag-filtered FDU retired FIFO.
    // A single reclaim lane is used to avoid a large simultaneous allocator
    // fan-in. The controller waits in DRAIN until this scan has completed.
    localparam int RECLAIM_TOTAL=STRUCT_FLOW_WINDOWS*STRUCT_FLOW_PC_MAX_RANGE;
    localparam int RECLAIM_W=$clog2(RECLAIM_TOTAL+1);
    logic [RECLAIM_W-1:0] reclaim_index;
    logic reclaim_started,reclaim_finished;
    wire [FLOW_W-1:0] reclaim_flow_idx = FLOW_W'(int'(reclaim_index)/STRUCT_FLOW_PC_MAX_RANGE);
    localparam int SLOT_INDEX_W = STRUCT_FLOW_PC_MAX_RANGE>1 ? $clog2(STRUCT_FLOW_PC_MAX_RANGE) : 1;
    wire [SLOT_INDEX_W-1:0] reclaim_slot_idx = SLOT_INDEX_W'(int'(reclaim_index)%STRUCT_FLOW_PC_MAX_RANGE);
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] reclaim_renamed =
        fdu_renamed[reclaim_flow_idx];
    wire [STRUCT_FLOW_PC_MAX_RANGE-1:0] reclaim_killed =
        fdu_killed[reclaim_flow_idx];
    wire [STRUCT_FLOW_PC_MAX_RANGE*_BITWIDTH_STRUCT_PHYREGS-1:0] reclaim_phy_array =
        fdu_phy[reclaim_flow_idx];
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0] reclaim_phy =
        reclaim_phy_array[int'(reclaim_slot_idx)*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS];
    wire reclaim_fire = fdu_active[reclaim_flow_idx] && reclaim_started && !reclaim_finished &&
        (int'(reclaim_index)<RECLAIM_TOTAL) &&
        reclaim_renamed[reclaim_slot_idx] && reclaim_killed[reclaim_slot_idx] &&
        (reclaim_phy != '0);
    // The recovery boundary itself can be a side effect (e.g. MRET). Its
    // completion waits for approval after redirect; only killed slots drain.
    wire [STRUCT_FLOW_WINDOWS-1:0] pending_reclaim;
    for(genvar w=0; w<STRUCT_FLOW_WINDOWS; w++) begin
        assign pending_reclaim[w]=|(fdu_killed[w] & fdu_renamed[w]);
    end
    assign o_reclaim_done = reclaim_finished && i_recovery_kill_active;
    always_ff @(posedge clk) begin
        if (!reset_n) begin reclaim_started<=1'b0;reclaim_finished<=1'b0;reclaim_index<='0;end
        else if (!i_recovery_kill_active) begin
            reclaim_started<=1'b0;reclaim_finished<=1'b0;reclaim_index<='0;
        end else if (windows_drained && !reclaim_finished) begin
            reclaim_started<=1'b1;
            if (reclaim_started) begin
                if (!(|pending_reclaim) || int'(reclaim_index)==RECLAIM_TOTAL-1) reclaim_finished<=1'b1;
                else reclaim_index<=reclaim_index+1'b1;
            end
        end
    end
    assign o_prm_unallocate_phyreg_valid = reclaim_fire ?
        {{(STRUCT_UNALLOCATE_PHYREG-1){1'b0}},1'b1} : fdu_retire_valid[head];
    assign o_prm_unallocate_phyreg_data = reclaim_fire ?
        {{((STRUCT_UNALLOCATE_PHYREG-1)*_BITWIDTH_STRUCT_PHYREGS){1'b0}},reclaim_phy} :
        fdu_retire_data[head];

    genvar request_lane, window_idx;
    generate
        for (request_lane = 0; request_lane < STRUCT_DECODE_NEW_INST; request_lane = request_lane+1) begin : G_REQUEST
            assign o_im_req_pc[request_lane*TAG_W +: TAG_W] =
                {batch_flow, (batch_pc + PC_W'(request_lane*IS_INST_PC_STEP))};
        end
        for (window_idx = 0; window_idx < STRUCT_FLOW_WINDOWS; window_idx = window_idx+1) begin : G_WINDOW
            flow_detect_unit #(
                .WINDOW_ID(window_idx), .FLOW_W(FLOW_W), .PC_W(PC_W),
                .PC_STEP(IS_INST_PC_STEP), .MAX_INSTRUCTIONS(STRUCT_FLOW_PC_MAX_RANGE),
                .DECODE(STRUCT_DECODE_NEW_INST), .DONE_CHANNELS(STRUCT_EX_OUT_RESULT_SUM),
                .DISCARD_CHANNELS(STRUCT_EX_OUT_RESULT_SUM+STRUCT_EX_CORES+2),
                .EXCEPTION_CHANNELS(STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST+1),
                .LOGICAL_REGS(IS_INST_REGS),.PHY_W(_BITWIDTH_STRUCT_PHYREGS),
                .RESOLVE_LANES(STRUCT_EX_BRANCH),.RETURNS(STRUCT_UNALLOCATE_PHYREG)
            ) U_FDU (
                .clk(clk), .reset_n(reset_n), .i_open(fdu_open[window_idx]), .i_start_pc(next_pc),
                .i_close(fdu_close[window_idx]), .i_close_next_pc(next_pc_next),
                .i_repair_next_pc(i_recovery_redirect_valid &&
                    i_recovery_kill_boundary[_BITWIDTH_FLOW_WINDOWS_PC-1:IS_INST_PC_BITWIDTH] ==
                    _BITWIDTH_STRUCT_FLOW_WINDOWS'(window_idx)),
                .i_repair_pc(i_recovery_redirect_pc),
                .o_next_pc(fdu_next[window_idx]),
                .o_exception(fdu_exception[window_idx]),.o_sidefx(fdu_sidefx[window_idx]),
                .o_cause(fdu_cause[window_idx]),.o_tval(fdu_tval[window_idx]),
                .i_baseline_map(i_rename_current_map),.o_baseline_map(fdu_baseline[window_idx]),
                .i_rename_rd_valid(i_rename_rd_valid),.i_rename_rd_tag(i_rename_rd_tag),
                .i_rename_rd(i_rename_rd),.i_rename_phy(i_rename_phy),
                .o_renamed(fdu_renamed[window_idx]),.o_rename_rd(fdu_rd[window_idx]),
                .o_rename_phy(fdu_phy[window_idx]),
                .i_sidefx_valid(i_sidefx_valid),.i_sidefx_tag(i_sidefx_tag),
                .i_exception_valid(i_exception_valid),.i_exception_tag(i_exception_tag),
                .i_exception_cause(i_exception_cause),.i_exception_tval(i_exception_tval),
                .o_active(fdu_active[window_idx]), .o_branch_drained(branch_drained[window_idx]),
                .i_branch_push(i_nel_jumpbranch_valid && (|i_nel_jumpbranch_data[2:1])),
                .i_branch_tag(i_nel_jumpbranch_pc),.i_branch_valid(i_wbc_branch_valid),
                .i_branch_data(i_wbc_branch_data),
                .o_closed(fdu_closed[window_idx]),.o_start_pc(fdu_start[window_idx]),
                .o_admitted(fdu_admitted[window_idx]),.o_done(fdu_completed[window_idx]),
                .o_discarded(fdu_discarded[window_idx]),
                .o_killed(fdu_killed[window_idx]),
                .i_reclaimed(reclaim_fire && reclaim_flow_idx==FLOW_W'(window_idx)),
                .i_reclaimed_slot(reclaim_slot_idx),
                .i_kill_active(i_recovery_kill_active),
                .i_kill_boundary(i_recovery_kill_boundary),
                .i_kill_inclusive(i_recovery_kill_inclusive),
                .i_kill_oldest_flow(i_recovery_oldest_flow),
                .i_window_id(FLOW_W'(window_idx)),
                .i_new_valid(i_nel_new_inst_valid), .i_new_pc(i_nel_new_inst_pc),
                .i_done_valid(i_wbc_done_pc_valid), .i_done_pc(i_wbc_done_pc_data),
                .i_discard_valid(i_squash_done_valid), .i_discard_pc(i_squash_done_pc),
                .i_retired_valid(i_nel_retired_phyreg_valid), .i_retired_data(i_nel_retired_phyreg_data),
                .i_retire_enable(reset_n && i_retire_permitted && (head == FLOW_W'(window_idx))),
                .o_retired_valid(fdu_retire_valid[window_idx]), .o_retired_data(fdu_retire_data[window_idx]),
                .o_release(fdu_release[window_idx])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            head <= '0; tail <= '0; current_valid <= 0; current_flow <= '0; current_used <= '0;
            next_pc <= '0; batch_active <= 0; batch_discard <= 0; batch_control <= 0;
            request_pending <= '0; batch_pc <= '0; batch_flow <= '0; batch_size <= '0;
            received <= '0; kept <= '0; renamed <= '0;
        end
        else begin
            head <= head_next; tail <= tail_next;
            current_valid <= current_valid_next; current_flow <= current_flow_next; current_used <= current_used_next;
            next_pc <= next_pc_next; batch_active <= batch_active_next;
            batch_discard <= batch_discard_next; batch_control <= batch_control_next;
            request_pending <= request_pending_next; batch_pc <= batch_pc_next; batch_flow <= batch_flow_next;
            batch_size <= batch_size_next; received <= received_next; kept <= kept_next; renamed <= renamed_next;
`ifndef SYNTHESIS
            if (batch_active && ((recv_sum > int'(batch_size)) || (rename_sum > keep_sum)))
                $error("FCL response/rename accounting violated the single in-order fetch-bundle contract");
            if (used_sum > STRUCT_FLOW_PC_MAX_RANGE) $error("FCL window capacity exceeded");
`endif
        end
    end

    always_comb begin
        head_next = head; tail_next = tail;
        current_valid_next = current_valid; current_flow_next = current_flow; current_used_next = current_used;
        next_pc_next = next_pc;
        batch_active_next = batch_active; batch_discard_next = batch_discard; batch_control_next = batch_control;
        request_pending_next = request_pending & ~i_im_req_pc_get;
        batch_pc_next = batch_pc; batch_flow_next = batch_flow; batch_size_next = batch_size;
        received_next = received; kept_next = kept; renamed_next = renamed;
        fdu_open = '0; fdu_close = '0;
        recv_sum = int'(received); keep_sum = int'(kept); rename_sum = int'(renamed);
        used_sum = int'(current_used); request_size = 0;

        if (reset_n) begin
            // Circular IDs are allocated and released in creation order. A newer
            // completed window cannot release a register still read by an older one.
            if (fdu_release[head]) head_next = (int'(head) == STRUCT_FLOW_WINDOWS-1)? '0 : head+1'b1;
            if (!i_recovery_stall && !current_valid && !batch_active && !fdu_active[tail]) begin
                fdu_open[tail] = 1'b1;
                current_valid_next = 1'b1; current_flow_next = tail; current_used_next = '0;
                tail_next = (int'(tail) == STRUCT_FLOW_WINDOWS-1)? '0 : tail+1'b1;
            end
            if (!i_recovery_stall && current_valid && !batch_active) begin
                request_size = STRUCT_FLOW_PC_MAX_RANGE-int'(current_used);
                if (request_size > STRUCT_DECODE_NEW_INST) request_size = STRUCT_DECODE_NEW_INST;
                batch_active_next = 1'b1; batch_discard_next = 0; batch_control_next = 0;
                batch_pc_next = next_pc; batch_flow_next = current_flow;
                batch_size_next = BATCH_W'(request_size);
                received_next = '0; kept_next = '0; renamed_next = '0;
                next_pc_next = next_pc + PC_W'(request_size*IS_INST_PC_STEP);
                for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane = lane+1)
                    request_pending_next[lane] = (lane < request_size);
            end

            if (batch_active) begin
                for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane = lane+1) begin
                    if (i_nel_recv_valid[lane]) recv_sum = recv_sum+1;
                    if (i_nel_recv_keep[lane]) keep_sum = keep_sum+1;
                    if (i_nel_new_inst_valid[lane]) begin rename_sum = rename_sum+1; used_sum = used_sum+1; end
                end
                received_next = BATCH_W'(recv_sum); kept_next = BATCH_W'(keep_sum); renamed_next = BATCH_W'(rename_sum);
                current_used_next = USED_W'(used_sum);
                if (i_nel_recv_control) batch_discard_next = 1'b1;

                if (i_nel_jumpbranch_valid) begin
                    batch_control_next = 1'b1;
                    // The initial plugin predicts fall-through for conditional branches
                    // and JALR; direct JAL has a statically known target.
                    // The window closes at this control, but younger windows
                    // may now be fetched before this branch resolves.
                    if (i_nel_jumpbranch_data[1] || i_nel_jumpbranch_data[2])
                        next_pc_next = i_nel_predict_target;
                    else next_pc_next = i_nel_jumpbranch_data[3 +: PC_W];
                end
                // Wait for all requested responses, including discarded suffixes,
                // and for every retained instruction to actually commit its rename.
                if (!(|request_pending_next) && (recv_sum == int'(batch_size)) && (rename_sum == keep_sum)) begin
                    batch_active_next = 1'b0; batch_discard_next = 1'b0;
                    if ((batch_control_next && next_pc_next != batch_pc + PC_W'(rename_sum*IS_INST_PC_STEP)) || (used_sum == STRUCT_FLOW_PC_MAX_RANGE)) begin
                        fdu_close[current_flow] = 1'b1; current_valid_next = 1'b0;
                    end
                end
            end
            // EX branch results are consumed by the speculative checkpoint
            // controller, not the legacy single-branch pending logic.
            if (i_recovery_redirect_valid) begin
                next_pc_next = i_recovery_redirect_pc;
                batch_active_next = 1'b0;
                batch_discard_next = 1'b0;
                batch_control_next = 1'b0;
                request_pending_next = '0;
                current_valid_next = 1'b0;
                received_next='0; kept_next='0; renamed_next='0;
                // Squashed windows can only be reclaimed when their FDU
                // receives terminal completion/discard for every admission.
                for (int w=0;w<STRUCT_FLOW_WINDOWS;w++)
                    if (fdu_active[w]) fdu_close[w]=1'b1;
            end
        end
    end
endmodule

// A window retains retired register numbers until it is closed, all admitted
// instructions complete, and the FCL grants this oldest window the return port.
module flow_detect_unit #(
    parameter int WINDOW_ID = 0,
    parameter int FLOW_W = 3,
    parameter int PC_W = 32,
    parameter int PC_STEP = 4,
    parameter int MAX_INSTRUCTIONS = 16,
    parameter int DECODE = 2,
    parameter int DONE_CHANNELS = 5,
    parameter int DISCARD_CHANNELS = 10,
    parameter int EXCEPTION_CHANNELS = 5, RESOLVE_LANES=1,
    parameter int LOGICAL_REGS=32,PHY_W=6,
    parameter int LOG_W=(LOGICAL_REGS>1?$clog2(LOGICAL_REGS):1),
    parameter int RETURNS = 4,
    localparam int TAG_W = FLOW_W+PC_W,
    localparam int RETIRED_W = PHY_W+TAG_W,
    localparam int COUNT_W = (MAX_INSTRUCTIONS > 1)? $clog2(MAX_INSTRUCTIONS+1) : 1
) (
    input logic clk, reset_n,
    input logic i_open, i_close,
    output wire o_branch_drained,
    input wire i_branch_push,
    input wire [TAG_W-1:0] i_branch_tag,
    input wire [RESOLVE_LANES-1:0] i_branch_valid,
    input wire [RESOLVE_LANES*(TAG_W+PC_W)-1:0] i_branch_data,
    input wire i_reclaimed,
    input wire [(MAX_INSTRUCTIONS>1?$clog2(MAX_INSTRUCTIONS):1)-1:0] i_reclaimed_slot,
    input logic i_kill_active,i_kill_inclusive,
    input logic [FLOW_W-1:0] i_kill_oldest_flow,i_window_id,
    input logic [TAG_W-1:0] i_kill_boundary,
    output logic [MAX_INSTRUCTIONS-1:0] o_killed,
    input logic [LOGICAL_REGS*PHY_W-1:0] i_baseline_map,
    output logic [LOGICAL_REGS*PHY_W-1:0] o_baseline_map,
    input logic [DECODE-1:0] i_rename_rd_valid,
    input logic [DECODE*TAG_W-1:0] i_rename_rd_tag,
    input logic [DECODE*LOG_W-1:0] i_rename_rd,
    input logic [DECODE*PHY_W-1:0] i_rename_phy,
    output logic [MAX_INSTRUCTIONS-1:0] o_renamed,
    output logic [MAX_INSTRUCTIONS*LOG_W-1:0] o_rename_rd,
    output logic [MAX_INSTRUCTIONS*PHY_W-1:0] o_rename_phy,
    input logic [PC_W-1:0] i_close_next_pc,
    input logic i_repair_next_pc,
    input logic [PC_W-1:0] i_repair_pc,
    output logic [PC_W-1:0] o_next_pc,
    input logic [DECODE-1:0] i_sidefx_valid,
    input logic [DECODE*TAG_W-1:0] i_sidefx_tag,
    input logic [EXCEPTION_CHANNELS-1:0] i_exception_valid,
    input logic [EXCEPTION_CHANNELS*TAG_W-1:0] i_exception_tag,
    input logic [EXCEPTION_CHANNELS*6-1:0] i_exception_cause,
    input logic [EXCEPTION_CHANNELS*PC_W-1:0] i_exception_tval,
    output logic [MAX_INSTRUCTIONS-1:0] o_exception,o_sidefx,
    output logic [MAX_INSTRUCTIONS*6-1:0] o_cause,
    output logic [MAX_INSTRUCTIONS*PC_W-1:0] o_tval,
    input logic [PC_W-1:0] i_start_pc,
    output logic o_active,
    output logic o_closed,
    output logic [PC_W-1:0] o_start_pc,
    output wire [MAX_INSTRUCTIONS-1:0] o_admitted,o_done,o_discarded,
    input logic [DECODE-1:0] i_new_valid,
    input logic [DECODE*TAG_W-1:0] i_new_pc,
    input logic [DISCARD_CHANNELS-1:0] i_discard_valid,
    input logic [DISCARD_CHANNELS*TAG_W-1:0] i_discard_pc,
    input logic [DONE_CHANNELS-1:0] i_done_valid,
    input logic [DONE_CHANNELS*TAG_W-1:0] i_done_pc,
    input logic [DECODE-1:0] i_retired_valid,
    input logic [DECODE*RETIRED_W-1:0] i_retired_data,
    input logic i_retire_enable,
    output wire [RETURNS-1:0] o_retired_valid,
    output wire [RETURNS*PHY_W-1:0] o_retired_data,
    output wire o_release
);
    localparam int IDX_W = MAX_INSTRUCTIONS>1 ? $clog2(MAX_INSTRUCTIONS) : 1;
    // A tag is unique for the lifetime of the window. Only the low word
    // address bits are required to recover an admitted slot in that window.
    // Explicit expressions keep each continuous assignment's dependencies local.
    // The power-of-two case only needs the low slot-index bits of word addresses.

    function automatic logic belongs(input logic [TAG_W-1:0] tag_value);
        return tag_value[TAG_W-1:PC_W]==FLOW_W'(WINDOW_ID);
    endfunction

    logic [MAX_INSTRUCTIONS-1:0] admitted, completed, discarded, old_valid;
    logic [PHY_W-1:0] old_phy[MAX_INSTRUCTIONS];
    logic [COUNT_W-1:0] retire_cursor;
    logic fault_present;
    logic [IDX_W-1:0] fault_slot;
    logic [5:0] fault_cause;
    logic [PC_W-1:0] fault_value;
    logic fault_new;
    logic [IDX_W-1:0] first_slot;
    logic [5:0] first_cause;
    logic [PC_W-1:0] first_value;
    always_comb begin
        fault_new=0;
        first_slot=fault_slot;
        first_cause=fault_cause;
        first_value=fault_value;
        for (int e=0;e<EXCEPTION_CHANNELS;e++) begin
            if (i_exception_valid[e] && belongs(i_exception_tag[e*TAG_W +: TAG_W]) &&
                ((!fault_present && !fault_new) ||
                 (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_exception_tag[e*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_exception_tag[e*TAG_W +: PC_W])-o_start_pc)/PC_STEP)) < first_slot)) begin
                fault_new=1;
                first_slot=(((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_exception_tag[e*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_exception_tag[e*TAG_W +: PC_W])-o_start_pc)/PC_STEP));
                first_cause=i_exception_cause[e*6 +: 6];
                first_value=i_exception_tval[e*PC_W +: PC_W];
            end
        end
    end
    wire [FLOW_W-1:0] distance_to_flow=i_window_id-i_kill_oldest_flow;
    wire [FLOW_W-1:0] distance_to_boundary=i_kill_boundary[TAG_W-1:PC_W]-i_kill_oldest_flow;
    wire [IDX_W-1:0] boundary_slot=(((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_kill_boundary[0 +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_kill_boundary[0 +: PC_W])-o_start_pc)/PC_STEP));
    logic [MAX_INSTRUCTIONS-1:0] await_outcome;
    assign o_branch_drained=!(|await_outcome);
    wire retire=o_branch_drained && reset_n && o_active && o_closed && i_retire_enable &&
        admitted==(completed|discarded);
    assign o_release=retire && int'(retire_cursor)>=MAX_INSTRUCTIONS;
    assign o_admitted=admitted;
    assign o_done=completed;
    assign o_discarded=discarded;
    for(genvar lane=0;lane<RETURNS;lane++) begin : G_RETIRE
        wire [IDX_W-1:0] index=IDX_W'(int'(retire_cursor)+lane);
        assign o_retired_valid[lane]=retire && int'(retire_cursor)+lane<MAX_INSTRUCTIONS &&
            old_valid[index] && !o_killed[index];
        assign o_retired_data[lane*PHY_W +: PHY_W]=old_phy[index];
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            o_active<=0; o_closed<=0; o_start_pc<='0; o_next_pc<='0;
            o_baseline_map<='0; retire_cursor<='0; fault_present<=0;
            fault_slot<='0; fault_cause<='0; fault_value<='0;
        end else if (i_open) begin
            o_active<=1; o_closed<=0; o_start_pc<=i_start_pc;
            o_baseline_map<=i_baseline_map; retire_cursor<='0; fault_present<=0;
        end else if (o_active) begin
            if(i_close) o_closed<=1;
            if(i_repair_next_pc) o_next_pc<=i_repair_pc;
            else if(i_close && !o_closed) o_next_pc<=i_close_next_pc;
            if(fault_new) begin
                fault_present<=1; fault_slot<=first_slot; fault_cause<=first_cause; fault_value<=first_value;
            end
            if(o_release) o_active<=0;
            else if(retire) retire_cursor<=COUNT_W'((int'(retire_cursor)+RETURNS<MAX_INSTRUCTIONS) ?
                int'(retire_cursor)+RETURNS : MAX_INSTRUCTIONS);
        end
    end

    for (genvar s=0;s<MAX_INSTRUCTIONS;s++) begin : G_SLOT
        wire [DECODE-1:0] add_slot,rename_slot,retire_slot,side_slot;
        wire [DONE_CHANNELS-1:0] done_slot;
        wire [DISCARD_CHANNELS-1:0] discard_slot;
        wire [EXCEPTION_CHANNELS-1:0] exception_slot;
        for(genvar d=0;d<DECODE;d++) begin : G_DECODE
            assign add_slot[d]=i_new_valid[d] && belongs(i_new_pc[d*TAG_W +: TAG_W]) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_new_pc[d*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_new_pc[d*TAG_W +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
            assign rename_slot[d]=add_slot[d] && i_rename_rd_valid[d];
            assign retire_slot[d]=add_slot[d] && i_retired_valid[d];
            assign side_slot[d]=i_sidefx_valid[d] && belongs(i_sidefx_tag[d*TAG_W +: TAG_W]) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_sidefx_tag[d*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_sidefx_tag[d*TAG_W +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
        end
        for(genvar e=0;e<DONE_CHANNELS;e++)
            assign done_slot[e]=i_done_valid[e] && belongs(i_done_pc[e*TAG_W +: TAG_W]) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_done_pc[e*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_done_pc[e*TAG_W +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
        for(genvar e=0;e<DISCARD_CHANNELS;e++)
            assign discard_slot[e]=i_discard_valid[e] && belongs(i_discard_pc[e*TAG_W +: TAG_W]) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_discard_pc[e*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_discard_pc[e*TAG_W +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
        for(genvar e=0;e<EXCEPTION_CHANNELS;e++)
            assign exception_slot[e]=i_exception_valid[e] && belongs(i_exception_tag[e*TAG_W +: TAG_W]) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_exception_tag[e*TAG_W +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_exception_tag[e*TAG_W +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
        wire [RESOLVE_LANES-1:0] resolved_here;
        for(genvar b=0;b<RESOLVE_LANES;b++) begin : G_RESOLVE
            wire [TAG_W-1:0] tag_value=i_branch_data[b*(TAG_W+PC_W) +: TAG_W];
            assign resolved_here[b]=i_branch_valid[b] && belongs(tag_value) &&
                (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((tag_value[0 +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((tag_value[0 +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s);
        end
        // Discard on the result bus only accounts for WBC. A separately
        // pipelined branch outcome still owns its tag until it arrives.
        always_ff @(posedge clk) begin
            if(!reset_n) await_outcome[s]<=0;
            else if(i_open || (|resolved_here) || (|exception_slot) ||
                    (|discard_slot[DISCARD_CHANNELS-1:DONE_CHANNELS])) await_outcome[s]<=0;
            else if(o_active && i_branch_push && belongs(i_branch_tag) &&
                    (((PC_STEP & (PC_STEP-1))==0) ? (IDX_W'((i_branch_tag[0 +: PC_W])/PC_STEP) - IDX_W'(o_start_pc/PC_STEP)) : IDX_W'(((i_branch_tag[0 +: PC_W])-o_start_pc)/PC_STEP))==IDX_W'(s)) await_outcome[s]<=1;
        end
        assign o_exception[s]=fault_present && fault_slot==IDX_W'(s);
        assign o_cause[s*6 +: 6]=fault_cause;
        assign o_tval[s*PC_W +: PC_W]=fault_value;
        always_ff @(posedge clk) begin
            for(int d=0;d<DECODE;d++) begin
                if(rename_slot[d]) begin
                    o_rename_phy[s*PHY_W +: PHY_W]<=i_rename_phy[d*PHY_W +: PHY_W];
                    o_rename_rd[s*LOG_W +: LOG_W]<=i_rename_rd[d*LOG_W +: LOG_W];
                end
                if(retire_slot[d]) old_phy[s]<=i_retired_data[d*RETIRED_W+TAG_W +: PHY_W];
            end
        end
        always_ff @(posedge clk) begin
            if(!reset_n) begin
                admitted[s]<=0; completed[s]<=0; discarded[s]<=0; old_valid[s]<=0;
                o_killed[s]<=0; o_renamed[s]<=0; o_sidefx[s]<=0;
            end else if(i_open) begin
                admitted[s]<=0; completed[s]<=0; discarded[s]<=0; old_valid[s]<=0;
                o_killed[s]<=0; o_renamed[s]<=0; o_sidefx[s]<=0;
            end else if(o_active) begin
                if(|add_slot) admitted[s]<=1;
                if(|done_slot || |exception_slot) completed[s]<=1;
                if(|discard_slot) discarded[s]<=1;
                if(|retire_slot) old_valid[s]<=1;
                if(|rename_slot) o_renamed[s]<=1;
                if(i_reclaimed && i_reclaimed_slot==IDX_W'(s)) o_renamed[s]<=0;
                if(|side_slot) o_sidefx[s]<=1;
                if(i_kill_active && admitted[s] && (distance_to_flow>distance_to_boundary ||
                   (distance_to_flow==distance_to_boundary && (s>int'(boundary_slot) ||
                   (i_kill_inclusive && IDX_W'(s)==boundary_slot))))) o_killed[s]<=1;
            end
        end
    end
endmodule
