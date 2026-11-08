`timescale 1ns/1ps
// Ordered memory-lane atomic engine. External arbiter must drain competing accesses
// before granting lock_request and exclude all competitors until its release.
// Reservation granule: one aligned physical word. No cache/exclusive AXI assumed.
module rv32_atomic #(
    parameter logic [31:0] RAM_BASE=32'h00020000,
    parameter logic [31:0] RAM_LIMIT=32'h00030000
) (
    input logic clk,reset_n,flush,clear_reservation,
    input logic invalidate,
    input logic [31:0] invalidate_address,
    input logic local_store,
    input logic [31:0] local_store_address,
    input logic valid,
    output wire ready,
    input logic [7:0] uop,
    input logic [31:0] address,operand,
    output wire result_valid,
    input logic result_ready,
    output logic [31:0] result,
    output logic result_fault,
    output logic [4:0] result_cause,
    output wire lock_request,
    input logic lock_grant,
    output wire [31:0] lock_address,
    output wire request_valid,
    input logic request_ready,
    output wire request_store,
    output wire [31:0] request_address,request_data,
    input logic response_valid,
    output wire response_ready,
    input logic [31:0] response_data,
    input logic response_fault
);
    import rv32_pkg::*;
    typedef enum logic [2:0] {IDLE,LOCK,READ_REQ,READ_WAIT,WRITE_REQ,WRITE_WAIT,DONE,DRAIN} state_t;
    state_t state;
    logic [7:0] operation;
    logic [31:0] saved_address,saved_operand,write_value,old_value;
    logic reservation_valid,lr_invalidated;
    logic [31:0] reservation_address;
    wire invalidate_current=invalidate && invalidate_address[31:2]==saved_address[31:2];
    wire invalidating_reservation=(invalidate && invalidate_address[31:2]==reservation_address[31:2]) ||
        (local_store && local_store_address[31:2]==reservation_address[31:2]);
    function automatic logic [31:0] amo_value(input logic [7:0] op,input logic [31:0] old_data,new_data);
        case(op)
            U_AMOSWAP: return new_data;
            U_AMOADD: return old_data+new_data;
            U_AMOXOR: return old_data^new_data;
            U_AMOAND: return old_data&new_data;
            U_AMOOR: return old_data|new_data;
            U_AMOMIN: return $signed(old_data)<$signed(new_data)?old_data:new_data;
            U_AMOMAX: return $signed(old_data)>$signed(new_data)?old_data:new_data;
            U_AMOMINU: return old_data<new_data?old_data:new_data;
            U_AMOMAXU: return old_data>new_data?old_data:new_data;
            default: return new_data;
        endcase
    endfunction
    assign ready=reset_n && !flush && state==IDLE;
    assign result_valid=state==DONE && !flush;
    assign lock_request=reset_n && state!=IDLE && state!=DONE;
    assign lock_address=saved_address;
    assign request_valid=reset_n && !flush && (state==READ_REQ || state==WRITE_REQ);
    assign request_store=state==WRITE_REQ;
    assign request_address=saved_address;
    assign request_data=write_value;
    assign response_ready=reset_n && (state==READ_WAIT || state==WRITE_WAIT || state==DRAIN);
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            state<=IDLE; operation<=0; saved_address<=0; saved_operand<=0;
            write_value<=0; old_value<=0; result<=0; result_fault<=0; result_cause<=0;
            reservation_valid<=0; reservation_address<=0; lr_invalidated<=0;
        end else begin
            if(invalidate_current || clear_reservation) lr_invalidated<=1;
            case(state)
                IDLE: if(valid && ready) begin
                    operation<=uop; saved_address<=address; saved_operand<=operand;
                    result<=0; result_fault<=0; result_cause<=0; lr_invalidated<=0;
                    if(uop==U_LR) reservation_valid<=0; // A new LR replaces the previous reservation.
                    if(address[1:0]!=0 || address<RAM_BASE || address>=RAM_LIMIT) begin
                        result_fault<=1;
                        result_cause<=address[1:0]!=0?(uop==U_LR?5'd4:5'd6):(uop==U_LR?5'd5:5'd7);
                        state<=DONE;
                        if(uop==U_SC) reservation_valid<=0;
                    end else state<=LOCK;
                end
                LOCK: if(lock_grant) begin
                    lr_invalidated<=0;
                    if(operation==U_SC) begin
                        // Check again at ownership grant, including same-edge snoops.
                        reservation_valid<=0;
                        if(reservation_valid && reservation_address==saved_address && !invalidate_current && !clear_reservation && !invalidating_reservation) begin
                            write_value<=saved_operand; state<=WRITE_REQ;
                        end else begin result<=1; state<=DONE; end
                    end else state<=READ_REQ;
                end
                READ_REQ: if(request_ready) state<=READ_WAIT;
                READ_WAIT: if(response_valid) begin
                    if(response_fault) begin
                        result_fault<=1; result_cause<=operation==U_LR?5'd5:5'd7; state<=DONE;
                    end else if(operation==U_LR) begin
                        result<=response_data; state<=DONE;
                        reservation_address<=saved_address;
                        reservation_valid<=!lr_invalidated && !invalidate_current && !clear_reservation;
                    end else begin
                        old_value<=response_data; write_value<=amo_value(operation,response_data,saved_operand);
                        state<=WRITE_REQ;
                    end
                end
                WRITE_REQ: if(request_ready) state<=WRITE_WAIT;
                WRITE_WAIT: if(response_valid) begin
                    result<=operation==U_SC?32'b0:old_value;
                    result_fault<=response_fault; result_cause<=5'd7; state<=DONE;
                end
                DONE: if(result_ready) state<=IDLE;
                DRAIN: if(response_valid) state<=IDLE;
                default: state<=IDLE;
            endcase
            if(invalidating_reservation || clear_reservation) reservation_valid<=0;
            if(flush) begin
                // Head-only issue prevents a normal speculative flush once a
                // write is published. A canceled read still drains its response.
                if((state==READ_WAIT || state==WRITE_WAIT || state==DRAIN) && !response_valid) state<=DRAIN;
                else state<=IDLE;
                if(operation==U_LR && state!=IDLE) reservation_valid<=0;
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        if(valid && ready) assert(is_atomic(uop)) else $fatal(1,"Invalid atomic uop");
        assert(!(flush && state==WRITE_WAIT)) else $fatal(1,"Flush after atomic write publication violates head-only issue");
    end
    // synthesis translate_on
endmodule
