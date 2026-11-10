`timescale 1ns/1ps
// Independent, single-outstanding ready/valid unit per lane. Multiply operands
// are captured before the signed 33x33 product, separating RF forwarding from
// multiplication. Division is a 32-step restoring divider with sign correction.
module baseline_muldiv (
    input logic clk, reset_n, flush,
    input logic valid,
    output logic ready,
    input logic [7:0] uop,
    input logic [31:0] a,b,
    output logic result_valid,
    input logic result_ready,
    output logic [31:0] result
);
    import rv32_pkg::*;
    logic dividing, quotient_negative, remainder_negative, select_remainder;
    logic [31:0] quotient, divisor;
    logic [32:0] remainder;
    logic [5:0] steps;
    logic signed [32:0] mul_a,mul_b;
    logic mul_pending, mul_high;
    logic signed [65:0] product;
    logic [32:0] trial, rem_next;
    logic [31:0] quot_next;
    logic signed_div;
    always_comb begin
        product=mul_a*mul_b;
        signed_div=uop==U_DIV || uop==U_REM;
        trial={remainder[31:0],quotient[31]};
        rem_next=trial;
        quot_next={quotient[30:0],1'b0};
        if(trial>={1'b0,divisor}) begin rem_next=trial-{1'b0,divisor}; quot_next[0]=1; end
    end
    assign ready=reset_n && !flush && !dividing && !mul_pending && !result_valid;
    // Unreset data registers permit DSP input-register packing. Pending/valid
    // are reset/flushed, so uncaptured or cancelled operands cannot publish.
    always_ff @(posedge clk) begin
        if(valid && ready && uop<=U_MULHU) begin
            mul_a<=$signed({(uop==U_MULH || uop==U_MULHSU) && a[31],a});
            mul_b<=$signed({(uop==U_MULH) && b[31],b});
            mul_high<=uop!=U_MUL;
        end
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            dividing<=0; mul_pending<=0; result_valid<=0; result<=0; quotient<=0; divisor<=0;
            remainder<=0; steps<=0; quotient_negative<=0; remainder_negative<=0; select_remainder<=0;
        end else if(flush) begin dividing<=0; mul_pending<=0; result_valid<=0; end
        else begin
            if(result_valid && result_ready) result_valid<=0;
            if(mul_pending) begin
                result<=mul_high?product[63:32]:product[31:0];
                result_valid<=1;
                mul_pending<=0;
            end
            if(valid && ready) begin
                if(uop<=U_MULHU) begin
                    mul_pending<=1;
                end else if(b==0) begin
                    result<=(uop==U_REM || uop==U_REMU)?a:32'hffffffff; result_valid<=1;
                end else begin
                    quotient<=signed_div && a[31] ? -a:a;
                    divisor<=signed_div && b[31] ? -b:b;
                    remainder<=0; steps<=32; dividing<=1;
                    quotient_negative<=signed_div && (a[31]^b[31]);
                    remainder_negative<=signed_div && a[31];
                    select_remainder<=uop==U_REM || uop==U_REMU;
                end
            end
            if(dividing) begin
                quotient<=quot_next; remainder<=rem_next; steps<=steps-1'b1;
                if(steps==1) begin
                    dividing<=0; result_valid<=1;
                    if(select_remainder) result<=remainder_negative?-rem_next[31:0]:rem_next[31:0];
                    else result<=quotient_negative?-quot_next:quot_next;
                end
            end
        end
    end
endmodule
