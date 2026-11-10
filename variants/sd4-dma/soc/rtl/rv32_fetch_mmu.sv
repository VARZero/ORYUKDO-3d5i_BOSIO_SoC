`timescale 1ns/1ps
// Translate each instruction of a three-word bundle independently. Crossing a
// page never assumes physical contiguity. Bare M-mode retains its fast path.
module rv32_fetch_mmu #(
    parameter logic [31:0] PT_BASE=32'h20000, PT_LIMIT=32'h30000
) (
    input logic clk,reset_n,tlb_flush,
    input logic valid,
    output wire ready,
    input logic [31:0] pc,satp,
    input logic [1:0] privilege,
    input logic sum,mxr,
    output wire result_valid,
    input logic result_ready,
    output wire [95:0] instructions,
    output wire [14:0] causes,
    output wire physical_valid,
    input logic physical_ready,
    output wire [31:0] physical_pc,
    input logic physical_response_valid,
    output wire physical_response_ready,
    input logic [95:0] physical_instructions,
    input logic [2:0] physical_fault,
    output wire pt_valid,
    input logic pt_ready,
    output wire [31:0] pt_address,
    input logic pt_response_valid,
    output wire pt_response_ready,
    input logic [31:0] pt_data,
    input logic pt_fault
);
    typedef enum logic [2:0] {IDLE,BARE_WAIT,XLATE,XLATE_WAIT,PHYS_REQ,PHYS_WAIT,DONE} state_t;
    state_t state;
    logic [31:0] base,context_satp,pa;
    logic [1:0] context_priv,index;
    logic context_sum,context_mxr;
    logic [95:0] words;
    logic [14:0] faults;
    wire bare=privilege==3 || !satp[31];
    wire x_ready,x_valid,x_fault;
    wire [4:0] x_cause;
    wire [31:0] x_address;
    assign ready=reset_n && state==IDLE && (!bare || physical_ready);
    assign physical_valid=reset_n && ((state==IDLE && valid && bare) || state==PHYS_REQ);
    assign physical_pc=state==IDLE?pc:pa;
    assign physical_response_ready=state==BARE_WAIT?result_ready:state==PHYS_WAIT;
    assign result_valid=state==DONE || (state==BARE_WAIT && physical_response_valid);
    assign instructions=state==BARE_WAIT?physical_instructions[95:0]:words;
    for(genvar n=0;n<3;n++) assign causes[n*5+:5]=state==BARE_WAIT?(physical_fault[n]?5'd1:5'd0):faults[n*5+:5];
    rv32_sv32 #(.PT_BASE(PT_BASE),.PT_LIMIT(PT_LIMIT)) walker (
        .clk(clk),.reset_n(reset_n),.flush(tlb_flush),.valid(state==XLATE),.ready(x_ready),
        .virtual_address(base+{28'b0,index,2'b0}),.satp(context_satp),.privilege(context_priv),
        .access_type(2'd0),.sum(context_sum),.mxr(context_mxr),
        .result_valid(x_valid),.result_ready(state==XLATE_WAIT),.physical_address(x_address),.fault(x_fault),.cause(x_cause),
        .request_valid(pt_valid),.request_ready(pt_ready),.request_address(pt_address),
        .response_valid(pt_response_valid),.response_ready(pt_response_ready),.response_data(pt_data),.response_fault(pt_fault));
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            state<=IDLE; base<=0; context_satp<=0; context_priv<=3; context_sum<=0; context_mxr<=0;
            index<=0; pa<=0; words<=0; faults<=0;
        end else case(state)
            IDLE: if(valid && ready) begin
                base<=pc; context_satp<=satp; context_priv<=privilege; context_sum<=sum; context_mxr<=mxr;
                index<=0; words<=0; faults<=0; state<=bare?BARE_WAIT:XLATE;
            end
            BARE_WAIT: if(physical_response_valid && result_ready) state<=IDLE;
            XLATE: if(x_ready) state<=XLATE_WAIT;
            XLATE_WAIT: if(x_valid) begin
                if(x_fault) begin
                    faults[index*5+:5]<=x_cause;
                    if(index==2) state<=DONE;
                    else begin index<=index+1'b1; state<=XLATE; end
                end else begin pa<=x_address; state<=PHYS_REQ; end
            end
            PHYS_REQ: if(physical_ready) state<=PHYS_WAIT;
            PHYS_WAIT: if(physical_response_valid) begin
                words[index*32+:32]<=physical_instructions[31:0];
                faults[index*5+:5]<=physical_fault[0]?5'd1:5'd0;
                if(index==2) state<=DONE;
                else begin index<=index+1'b1; state<=XLATE; end
            end
            DONE: if(result_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
