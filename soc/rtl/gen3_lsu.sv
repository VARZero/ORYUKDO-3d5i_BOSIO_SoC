`timescale 1ns/1ps
// The scheduler LSQ keeps the issuing head until this unit returns a terminal event.
module gen3_lsu #(parameter logic [31:0] RAM_BASE='h80000000, RAM_LIMIT='hc0000000)(
    output wire atomic_lock, input wire atomic_grant,
    input wire reservation_invalidate, input wire [31:0] reservation_address,
    input logic clk,reset_n,issue,kill,clear_reservation,tlb_flush,
    output wire ready,
    input logic [34:0] tag, input logic [5:0] rd,
    input logic [7:0] uop, input logic [31:0] va,operand,satp,
    input logic [1:0] privilege, input logic sum,mxr,
    output logic [34:0] saved_tag, output logic [5:0] saved_rd,
    output wire prepare, output wire effect_ready, input logic approve,
    output wire effect_done,effect_error,wb,ex_fault,
    output logic [31:0] value, output logic [4:0] cause, output logic [31:0] saved_va,
    output wire bus_valid,bus_store, input logic bus_ready,
    output wire [31:0] bus_address,bus_data, output wire [3:0] bus_mask,
    input logic response_valid,response_fault, input logic [31:0] response_data,
    output wire response_ready
);
    import rv32_pkg::*;
    typedef enum logic [3:0] {IDLE,XLATE,PREPARE,AUTH,BUS_REQ,BUS_WAIT,ATOM_START,ATOM_WAIT,RESULT} state_t;
    state_t state;
    logic [7:0] op;
    logic [31:0] data,pa;
    logic failed,authorized;
    wire is_store=op inside {U_SB,U_SH,U_SW};
    wire atomic=is_atomic(op);
    wire word_access=!(uop inside {U_LB,U_LBU,U_SB,U_LH,U_LHU,U_SH});
    wire misaligned=word_access ? (|va[1:0]) :
        ((uop inside {U_SH,U_LH,U_LHU}) && va[0]);
    wire issue_store=uop inside {U_SB,U_SH,U_SW} || (is_atomic(uop) && uop!=U_LR);
    wire walk_ready,translated,walk_fault,pt_valid,pt_ack;
    wire [31:0] translated_pa,pt_address;
    wire [4:0] walk_cause;
    rv32_sv32 #(.PT_BASE(RAM_BASE),.PT_LIMIT(RAM_LIMIT)) walk(.clk,.reset_n,.flush(tlb_flush),
        .valid(issue && !misaligned),.ready(walk_ready),.virtual_address(va),.satp,.privilege,
        .access_type(issue_store ? 2'd2 : 2'd1),.sum,.mxr,.result_valid(translated),
        .result_ready(state==XLATE),.physical_address(translated_pa),.fault(walk_fault),.cause(walk_cause),
        .request_valid(pt_valid),.request_ready(bus_ready && state==XLATE),.request_address(pt_address),
        .response_valid(response_valid && state==XLATE),.response_ready(pt_ack),.response_data,.response_fault);
    wire ar,ar_done,ar_fault,ar_valid,ar_store,ar_ack;
    wire [31:0] ar_result,ar_address,ar_wdata; wire [4:0] ar_cause;
    rv32_atomic #(.RAM_BASE(RAM_BASE),.RAM_LIMIT(RAM_LIMIT)) amo(.clk,.reset_n,.flush(1'b0),.clear_reservation,
        .invalidate(reservation_invalidate),.invalidate_address(reservation_address),.local_store(state==BUS_REQ && is_store && bus_ready),
        .local_store_address(pa),.valid(state==ATOM_START),.ready(ar),.uop(op),.address(pa),.operand(data),
        .result_valid(ar_done),.result_ready(state==ATOM_WAIT),.result(ar_result),.result_fault(ar_fault),
        .result_cause(ar_cause),.lock_request(atomic_lock),.lock_grant(atomic_grant),.lock_address(),
        .request_valid(ar_valid),.request_ready(bus_ready && state==ATOM_WAIT),.request_store(ar_store),
        .request_address(ar_address),.request_data(ar_wdata),.response_valid(response_valid && state==ATOM_WAIT),
        .response_ready(ar_ack),.response_data,.response_fault);
    assign ready=state==IDLE && walk_ready;
    assign prepare=state==PREPARE && !kill;
    assign effect_ready=state==AUTH && !kill;
    assign wb=state==RESULT && (!failed || (kill && !authorized));
    assign ex_fault=state==RESULT && failed && !authorized && !kill;
    assign effect_done=state==RESULT && authorized;
    assign effect_error=effect_done && failed;
    assign bus_valid=state==XLATE ? pt_valid : state==ATOM_WAIT ? ar_valid : state==BUS_REQ;
    assign bus_store=state==ATOM_WAIT ? ar_store : state==BUS_REQ && is_store;
    assign bus_address=state==XLATE ? pt_address : state==ATOM_WAIT ? ar_address : {pa[31:2],2'b0};
    assign bus_data=state==ATOM_WAIT ? ar_wdata : data << {pa[1:0],3'b000};
    assign bus_mask=state==BUS_REQ ? ((op inside {U_SB,U_LB,U_LBU} ? 4'b1 :
                       op inside {U_SH,U_LH,U_LHU} ? 4'b11 : 4'hf) << pa[1:0]) : 4'hf;
    assign response_ready=state==XLATE ? pt_ack : state==ATOM_WAIT ? ar_ack : state==BUS_WAIT;
    always_ff @(posedge clk) begin
        if(!reset_n) begin state<=IDLE; authorized<=0; failed<=0; end
        else case(state)
            IDLE: if(issue) begin
                saved_tag<=tag; saved_rd<=rd; saved_va<=va; op<=uop; data<=operand;
                value<=0; authorized<=0; failed<=misaligned; cause<=issue_store?6:4;
                state<=misaligned ? RESULT : XLATE;
            end
            XLATE: if(translated) begin
                pa<=translated_pa; failed<=walk_fault && !kill; cause<=walk_cause;
                if(kill || walk_fault) state<=RESULT;
                else state<=is_store || atomic || translated_pa<RAM_BASE || translated_pa>=RAM_LIMIT ? PREPARE : BUS_REQ;
            end
            PREPARE: state<=kill ? RESULT : AUTH;
            AUTH: if(kill) state<=RESULT;
                  else if(approve) begin authorized<=1; state<=atomic ? ATOM_START : BUS_REQ; end
            ATOM_START: if(ar) state<=ATOM_WAIT;
            ATOM_WAIT: if(ar_done) begin value<=ar_result; failed<=ar_fault; cause<=ar_cause; state<=RESULT; end
            BUS_REQ: if(bus_ready) state<=BUS_WAIT;
            BUS_WAIT: if(response_valid) begin
                value<=load_value(op,response_data,pa[1:0]); failed<=response_fault && !kill;
                cause<=is_store ? 7 : 5; state<=RESULT;
            end
            RESULT: state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
