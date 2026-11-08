`timescale 1ns/1ps
module gen3_cpu #(parameter logic [31:0] RAM_BASE='h80000000,RAM_LIMIT='hc0000000)(
    output wire atomic_lock, input wire atomic_grant,
    input wire reservation_invalidate, input wire [31:0] reservation_address,
    input logic clk,reset_n,scheduler_reset_n,timer_irq, input logic [63:0] timer_time,
    output wire if_valid, input logic if_ready, output wire [31:0] if_pc,
    input logic if_response_valid,output wire if_response_ready,input logic [95:0] if_data,input logic [2:0] if_fault,
    output wire mem_valid,mem_store,input logic mem_ready,
    output wire [31:0] mem_address,mem_write_data,output wire [3:0] mem_mask,
    input logic mem_response_valid,output wire mem_response_ready,input logic [31:0] mem_read_data,input logic mem_fault,
    output wire trap,trap_interrupt,output wire [31:0] trap_pc,trap_value,retire_pc,
    output wire [4:0] trap_cause,output wire retire
);
    import rv32_pkg::*;
    localparam int LANES[4]='{1,2,1,1};
    typedef struct packed {logic [5:0] rs2,rs1,rd; logic [31:0] imm; logic [7:0] op; logic [1:0] path; logic [34:0] tag;} entry_t;
    entry_t ex[5];
    logic [31:0] prf[64];
    wire [4:0] issue,take,accepted,wb,fault;
    wire [34:0] wb_tag[5]; wire [5:0] wb_rd[5];
    wire [31:0] wb_value[5],a[5],b[5],fault_value[5];
    wire [5:0] fault_code[5];
    wire [5*41-1:0] results;
    wire [174:0] exception_tags; wire [29:0] exception_phys,exception_causes;
    wire [159:0] exception_values; wire [5*$bits(entry_t)-1:0] issue_data;
    wire [34:0] boundary; wire [2:0] oldest,commit_flow;
    wire kill_active,inclusive,redirect,trap_request,irq;
    wire [31:0] redirect_pc,base_pc,vector,satp;
    wire [1:0] privilege,data_privilege;
    wire sum,mxr; wire tlb_flush; wire [4:0] irq_cause; wire [5:0] trap_code;
    wire [15:0] commit; wire [191:0] map;
    assign trap_cause=trap_code[4:0]; assign trap=trap_request;
    assign retire=|commit;
    // Trace the first slot retired this cycle. The full bitmap is used for counters.
    logic [3:0] first_slot;
    always_comb begin first_slot=0; for(int k=15;k>=0;k--) if(commit[k]) first_slot=4'(k); end
    assign retire_pc=base_pc+{26'b0,first_slot,2'b0};
    wire effect_req,effect_ack,effect_done,effect_error;
    wire [34:0] effect_tag;
    wire [5:0] effect_cause; wire [31:0] effect_tval;
    wire [2:0] prepare; wire [104:0] prepare_tags;
    wire branch_valid; wire [66:0] branch_data;

    wire [2:0] req,req_get,im,im_get;
    wire [104:0] req_tags; logic [104:0] response_tags;
    logic [2:0] requested;
    wire fetch_ready,fetch_done,fetch_ack;
    wire [95:0] instructions; wire [14:0] fetch_causes;
    wire ipt_req,ipt_ready,ipt_ack,ipt_rsp; wire [31:0] ipt_addr;
    logic barrier; logic [34:0] barrier_tag;
    wire [2:0] discard;
    wire sys_valid,mem_prepare;
    logic [34:0] sys_tag; wire [34:0] ls_tag;
    oryukdo_recovery_boundary #(.FLOWS(8),.SLOT_W(32),.LANES(3),.WRAPPING_PC(1)) kills (
        .i_recovery_active(kill_active),.i_oldest_flow(oldest),.i_boundary_tag(boundary),
        .i_boundary_inclusive(inclusive),.i_candidate_valid(3'b111),.i_candidate_tag({barrier_tag,sys_tag,ls_tag}),.o_kill(discard));
    // Unsent fetches during drain must still get their tagged response; the NEL discards them.
    wire can_fetch=!barrier || kill_active;
    assign req_get=req & {3{fetch_ready && can_fetch}};
    rv32_fetch_mmu #(.PT_BASE(RAM_BASE),.PT_LIMIT(RAM_LIMIT)) ifetch(.clk,.reset_n,.tlb_flush,.valid((|req) && can_fetch),
        .ready(fetch_ready),.pc(req_tags[31:0]),.satp,.privilege,.sum,.mxr,.result_valid(fetch_done),.result_ready(fetch_ack),
        .instructions,.causes(fetch_causes),.physical_valid(if_valid),.physical_ready(if_ready),.physical_pc(if_pc),
        .physical_response_valid(if_response_valid),.physical_response_ready(if_response_ready),.physical_instructions(if_data),
        .physical_fault(if_fault),.pt_valid(ipt_req),.pt_ready(ipt_ready),.pt_address(ipt_addr),.pt_response_valid(ipt_rsp),
        .pt_response_ready(ipt_ack),.pt_data(mem_read_data),.pt_fault(mem_fault));
    assign im=requested & {3{fetch_done}};
    assign fetch_ack=fetch_done && ((requested & ~im_get)==0);
    always_ff @(posedge clk) begin
        if(!reset_n) requested<=0;
        else if(|req_get) begin requested<=req_get; response_tags<=req_tags; end
        else requested<=requested & ~im_get;
    end
    wire [5:0] paths; wire [23:0] ops; wire [95:0] immediates; wire [14:0] rd;
    wire [29:0] rs; wire [2:0] writes,jump,indirect,branch,serial;
    for(genvar d=0;d<3;d++) begin: decode_lane
        wire [31:0] ins=instructions[d*32+:32],pc=response_tags[d*35+:32];
        wire [1:0] path; wire [7:0] op; wire [31:0] imm;
        wire wr,control,system_op,illegal; wire [4:0] dc,rs1,rs2;
        rv32_decode decode(.instruction(ins),.path,.uop(op),.immediate(imm),.rd(rd[d*5+:5]),.rs1,.rs2,
            .writes(wr),.control,.memory_op(),.store_op(),.serial_op(system_op),.exception(illegal),.cause(dc));
        wire [4:0] fetch_cause=fetch_causes[d*5+:5];
        wire bad=illegal || (fetch_cause!=0);
        wire [4:0] cause=fetch_cause!=0 ? fetch_cause : dc==11 ? 5'd8+{3'b0,privilege} : dc;
        assign ops[d*8+:8]=bad ? {3'b111,cause} : op;
        assign paths[d*2+:2]=bad ? 0 : path;
        assign immediates[d*32+:32]=bad ? (fetch_cause!=0 || dc==3 ? pc : dc==2 ? ins : 32'b0) : imm;
        assign rs[d*10+:10]={rs2,rs1}; assign writes[d]=wr && rd[d*5+:5]!=0 && !bad;
        assign serial[d]=system_op && !is_atomic(op) && !bad;
        // A checkpoint on each serial operation cuts the bundle at that PC. It is
        // resolved by the control lane independently of irrevocable CSR approval.
        assign jump[d]=!bad && op==U_JAL && imm[1:0]==0;
        assign indirect[d]=!bad && op==U_JALR;
        assign branch[d]=!bad && ((control && !jump[d] && !indirect[d]) || serial[d]);
    end
    wire barrier_retired=barrier && commit_flow==barrier_tag[34:32] &&
        (barrier_tag[31:0]-base_pc)<64 && commit[4'((barrier_tag[31:0]-base_pc)>>2)];
    always_ff @(posedge clk) begin
        if(!reset_n || redirect && trap_request || barrier_retired || (barrier && discard[2])) barrier<=0;
        else if(!kill_active) begin
            for(int d=0;d<3;d++) if(im[d] && im_get[d]) begin
                if(serial[d]) begin barrier<=1;barrier_tag<=response_tags[d*35+:35]; end
                if(jump[d] || indirect[d] || branch[d]) break;
            end
        end
    end
    oryukdo_gen3_scheduler #(.ASYNC_PORT_ISOLATION(1'b0),.STRUCT_EX_PATH(4),.STRUCT_RS_OUT_ENTRY(LANES),.STRUCT_LSQ_EX_PATH(3),
        .EX_INST_MICROOP_BITWIDTH(8)) scheduler(.clk,.reset_n(scheduler_reset_n),
        .o_im_req_pc_valid(req),.i_im_req_pc_get(req_get),.o_im_req_pc(req_tags),
        .i_im_recv_inst_valid(im),.o_im_recv_inst_get(im_get),.i_im_recv_pc(response_tags),.i_im_recv_inst(instructions),
        .i_nel_decode_exception('0),.i_nel_decode_expath(paths),.i_nel_decode_microop(ops),.i_nel_decode_rd(rd),
        .i_nel_decode_newreg(writes),.i_nel_decode_rs(rs),.i_nel_decode_imm(immediates),
        .i_nel_decode_jump(jump),.i_nel_decode_jump_reg(indirect),.i_nel_decode_branch(branch),
        .o_rs_entry_valid(issue),.i_rs_entry_get(take),.o_rs_entry_data(issue_data),.i_wbc_result_valid(wb),
        .i_wbc_result_data(results),.i_wbc_result_branch_valid(branch_valid),.i_wbc_result_branch_data(branch_data),
        .i_sidefx_valid(prepare),.i_sidefx_tag(prepare_tags),.i_exception_valid(fault),.i_exception_tag(exception_tags),
        .i_exception_phyreg(exception_phys),.i_exception_cause(exception_causes),.i_exception_tval(exception_values),
        .i_interrupt_pending(irq),.i_interrupt_cause({1'b0,irq_cause}),.i_trap_vector_pc(vector),
        .o_trap_csr_request(trap_request),.o_trap_epc(trap_pc),.o_trap_tval(trap_value),.o_trap_cause(trap_code),
        .o_trap_interrupt(trap_interrupt),.i_trap_csr_done(trap_request),
        .o_sidefx_valid(effect_req),.o_sidefx_tag(effect_tag),.i_sidefx_ready(effect_ack),.i_sidefx_done(effect_done),
        .i_sidefx_error(effect_error),.i_sidefx_error_cause(effect_cause),.i_sidefx_error_tval(effect_tval),
        .o_commit_fire(commit),.o_commit_flow(commit_flow),.o_commit_base_pc(base_pc),.o_redirect_valid(redirect),
        .o_redirect_pc(redirect_pc),.o_wbc_accept(accepted),.o_backend_kill_valid(kill_active),
        .o_backend_kill_tag(boundary),.o_backend_kill_inclusive(inclusive),.o_backend_oldest_flow(oldest),.o_rename_snapshot(map),
        .i_oryukdo_issue_kill('0),.i_oryukdo_result_kill('0),.i_predict_query_ready(1'b0),
        .i_predict_response_valid(1'b0),.i_predict_response_tag('0),.i_predict_response_target('0),.i_predict_response_taken(1'b0));
    for(genvar e=0;e<5;e++) begin: ex_lane
        assign ex[e]=issue_data[e*$bits(entry_t)+:$bits(entry_t)];
        // Explicit combinational dependencies include PRF writes and bypass
        // changes even when the source physical register number stays fixed.
        // A continuous call to a function reading module state can otherwise
        // leave stale operands in event-driven simulation.
        logic [31:0] source_a,source_b;
        always_comb begin
            source_a=prf[ex[e].rs1];
            source_b=prf[ex[e].rs2];
            for(int port=0;port<5;port++) begin
                if(accepted[port] && wb_rd[port]==ex[e].rs1) source_a=wb_value[port];
                if(accepted[port] && wb_rd[port]==ex[e].rs2) source_b=wb_value[port];
            end
            if(ex[e].rs1==0) source_a=0;
            if(ex[e].rs2==0) source_b=0;
        end
        assign a[e]=source_a; assign b[e]=source_b;
        assign results[e*41+:41]={wb_rd[e],wb_tag[e]};
        assign exception_tags[e*35+:35]=wb_tag[e]; assign exception_phys[e*6+:6]=wb_rd[e];
        assign exception_values[e*32+:32]=fault_value[e]; assign exception_causes[e*6+:6]=fault_code[e];
    end
    always_ff @(posedge clk) for(int e=0;e<5;e++) if(accepted[e] && wb_rd[e]!=0) prf[wb_rd[e]]<=wb_value[e];
    for(genvar e=1;e<=2;e++) begin: alu_lane
        wire [31:0] value; wire illegal; wire [4:0] cause;
        rv32_alu_execute alu(.uop(ex[e].op),.pc(ex[e].tag[31:0]),.a(a[e]),.b(b[e]),.immediate(ex[e].imm),
            .value,.next_pc(),.fault(illegal),.cause);
        logic valid,bad; logic [31:0] data; logic [34:0] tag; logic [5:0] dest;
        always_ff @(posedge clk) begin
            valid<=reset_n && issue[e];
            if(issue[e]) begin data<=value;tag<=ex[e].tag;dest<=ex[e].rd;bad<=illegal;end
        end
        assign take[e]=1; assign wb[e]=valid && !bad; assign fault[e]=valid && bad;
        assign wb_tag[e]=tag;assign wb_rd[e]=dest;assign wb_value[e]=data;assign fault_value[e]=0;assign fault_code[e]=2;
    end
    rv32_muldiv md(.clk,.reset_n,.flush(1'b0),.valid(issue[3]),.ready(take[3]),.uop(ex[3].op),
        .a(a[3]),.b(b[3]),.result_valid(wb[3]),.result_ready(1'b1),.result(wb_value[3]));
    logic [34:0] md_tag; logic [5:0] md_rd;
    always_ff @(posedge clk) if(issue[3] && take[3]) begin md_tag<=ex[3].tag; md_rd<=ex[3].rd;end
    assign wb_tag[3]=md_tag;assign wb_rd[3]=md_rd;assign fault[3]=0;assign fault_code[3]=0;assign fault_value[3]=0;

    wire ctrl_sys=ex[0].op inside {U_CSR,U_FENCE,U_MRET,U_SRET,U_SFENCE,U_WFI};
    wire [31:0] br_value,br_next,csr_value,csr_next;
    wire br_fault,csr_illegal; wire [4:0] br_cause;
    rv32_branch_execute bru(.uop(ex[0].op),.pc(ex[0].tag[31:0]),.a(a[0]),.b(b[0]),.immediate(ex[0].imm),
        .value(br_value),.next_pc(br_next),.fault(br_fault),.cause(br_cause));
    typedef enum logic [1:0] {FREE,WAIT_AUTH,COMPLETE} csr_state_t;
    csr_state_t cs;
    logic ctrl_valid,ctrl_fault,ctrl_branch;
    logic [31:0] ctrl_data,ctrl_tval,ctrl_target,sys_data,sys_operand,sys_ins;
    logic [34:0] ctrl_tag;logic [5:0] ctrl_rd,ctrl_code,sys_rd;logic [7:0] sys_op;
    wire sys_auth=cs==WAIT_AUTH && effect_req && effect_tag==sys_tag && !discard[1];
    wire sys_cancel=cs==WAIT_AUTH && discard[1];
    wire sys_end=cs==COMPLETE;
    // Flush both translation caches only when the ordered operation commits.
    // Conservatively flush on SATP writes as well as all SFENCE.VMA operands.
    assign tlb_flush=sys_end && emit_sys && (sys_op==U_SFENCE ||
        (sys_op==U_CSR && sys_ins[31:20]==12'h180));
    wire emit_sys=(sys_cancel || sys_end) && !ctrl_valid;
    wire ctrl_fire=issue[0] && take[0];
    assign take[0]=!ctrl_sys || cs==FREE;
    wire literal_fault=ex[0].op[7:5]==3'b111;
    wire ctrl_bad=literal_fault || (ctrl_sys ? csr_illegal : br_fault);
    wire use_saved=cs!=FREE;
    rv32_machine_csrs csr(.clk,.reset_n,.flush(1'b0),.reset_mtvec(0),.timer_irq,.time_value(timer_time),
        .issue(sys_auth),.issue_token({2'b0,sys_tag}),.uop(use_saved?sys_op:ex[0].op),
        .instruction(use_saved?sys_ins:ex[0].imm),.operand(use_saved?sys_operand:a[0]),.pc(use_saved?sys_tag[31:0]:ex[0].tag[31:0]),
        .read_value(csr_value),.next_pc(csr_next),.illegal(csr_illegal),
        .retire(sys_end && emit_sys),.retire_count(3'($countones(commit))),.retire_token({2'b0,sys_tag}),
        .trap,.trap_interrupt,.trap_pc,.trap_value,.trap_cause,.interrupt_request(irq),.interrupt_cause(irq_cause),
        .trap_vector(vector),.privilege,.data_privilege,.satp,.sum,.mxr);
    always_ff @(posedge clk) begin
        if(!reset_n) begin cs<=FREE; ctrl_valid<=0; ctrl_branch<=0; end
        else begin
            ctrl_valid<=ctrl_fire && (!ctrl_sys || ctrl_bad);
            ctrl_branch<=ctrl_fire && !literal_fault && (ctrl_sys || ex[0].op!=U_JAL || ex[0].imm[1:0]!=0);
            if(ctrl_fire) begin
                ctrl_tag<=ex[0].tag;ctrl_rd<=ex[0].rd;ctrl_data<=br_value;
                ctrl_target<=ctrl_sys ? csr_next : br_next;
                ctrl_fault<=ctrl_bad;ctrl_code<=literal_fault ? {1'b0,ex[0].op[4:0]} : ctrl_sys ? 6'd2 : {1'b0,br_cause};
                ctrl_tval<=literal_fault || ctrl_sys ? ex[0].imm : br_next;
                if(ctrl_sys && !ctrl_bad) begin
                    cs<=WAIT_AUTH;sys_tag<=ex[0].tag;sys_rd<=ex[0].rd;sys_op<=ex[0].op;
                    sys_operand<=a[0];sys_ins<=ex[0].imm;
                end
            end
            if(sys_auth) begin cs<=COMPLETE;sys_data<=csr_value; end
            if(emit_sys) cs<=FREE;
        end
    end
    assign branch_valid=ctrl_branch; assign branch_data={ctrl_target,ctrl_tag};
    assign wb[0]=ctrl_valid && !ctrl_fault || emit_sys;
    assign fault[0]=ctrl_valid && ctrl_fault;
    assign wb_value[0]=ctrl_valid?ctrl_data:sys_data;assign wb_tag[0]=ctrl_valid?ctrl_tag:sys_tag;
    assign wb_rd[0]=ctrl_valid?ctrl_rd:sys_rd;assign fault_code[0]=ctrl_code;assign fault_value[0]=ctrl_tval;
    assign sys_valid=ctrl_fire && ctrl_sys && !ctrl_bad;
    wire ls_ready,ls_effect,ls_error;wire [4:0] ls_cause;wire [31:0] ls_va;
    wire db_req,db_store,db_ready,db_rsp,db_ack; wire [31:0] db_addr,db_data;wire [3:0] db_mask;
    wire ls_approve=effect_req && effect_tag==ls_tag && ls_ready;
    gen3_lsu #(.RAM_BASE(RAM_BASE),.RAM_LIMIT(RAM_LIMIT)) lsu(.atomic_lock,.atomic_grant,.reservation_invalidate,.reservation_address,
        .clk,.reset_n,.tlb_flush,.issue(issue[4] && take[4]),.kill(discard[0]),
        .clear_reservation(trap || (sys_end && (sys_op==U_MRET || sys_op==U_SRET))),.ready(take[4]),
        .tag(ex[4].tag),.rd(ex[4].rd),.uop(ex[4].op),.va(is_atomic(ex[4].op)?a[4]:a[4]+ex[4].imm),.operand(b[4]),
        .satp,.privilege(data_privilege),.sum,.mxr,.saved_tag(ls_tag),.saved_rd(wb_rd[4]),.prepare(mem_prepare),
        .effect_ready(ls_ready),.approve(ls_approve),.effect_done(ls_effect),.effect_error(ls_error),.wb(wb[4]),
        .ex_fault(fault[4]),.value(wb_value[4]),.cause(ls_cause),.saved_va(ls_va),.bus_valid(db_req),.bus_store(db_store),
        .bus_ready(db_ready),.bus_address(db_addr),.bus_data(db_data),.bus_mask(db_mask),.response_valid(db_rsp),
        .response_fault(mem_fault),.response_data(mem_read_data),.response_ready(db_ack));
    assign wb_tag[4]=ls_tag;assign fault_value[4]=ls_va;assign fault_code[4]={1'b0,ls_cause};
    assign prepare={1'b0,mem_prepare,sys_valid};assign prepare_tags={35'b0,ls_tag,ex[0].tag};
    assign effect_ack=sys_auth || ls_approve;
    assign effect_done=(sys_end && emit_sys) || ls_effect;assign effect_error=ls_error;
    assign effect_cause={1'b0,ls_cause}; assign effect_tval=ls_va;
    // Single-hart physical memory bus. Only the LSU writes; page walks are reads.
    logic busy,fetch_owner;
    logic grant_held,held_fetch;
    wire grant_fetch=grant_held ? held_fetch : !db_req && ipt_req;
    always_ff @(posedge clk) begin
        if(!reset_n || mem_ready) grant_held<=0;
        else if(mem_valid && !grant_held) begin grant_held<=1; held_fetch<=grant_fetch; end
    end
    assign mem_valid=!busy && (db_req || ipt_req);assign mem_store=!grant_fetch && db_store;
    assign mem_address=grant_fetch?ipt_addr:db_addr;assign mem_write_data=db_data;assign mem_mask=grant_fetch?4'hf:db_mask;
    assign ipt_ready=!busy && grant_fetch && mem_ready;assign db_ready=!busy && !grant_fetch && mem_ready;
    assign ipt_rsp=busy && fetch_owner && mem_response_valid;assign db_rsp=busy && !fetch_owner && mem_response_valid;
    assign mem_response_ready=busy && (fetch_owner?ipt_ack:db_ack);
    always_ff @(posedge clk) begin
        if(!reset_n) busy<=0;
        else if(mem_valid && mem_ready) begin busy<=1;fetch_owner<=grant_fetch;end
        else if(mem_response_valid && mem_response_ready) busy<=0;
    end
endmodule
