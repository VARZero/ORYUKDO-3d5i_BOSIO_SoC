`timescale 1ns/1ps
module reviewed_cpu_reset(input wire clk,reset_n,output wire local_reset_n);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [3:0] pin_release='0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [1:0] local_release='0;
    always_ff @(posedge clk or negedge reset_n)
        if(!reset_n) pin_release<='0;
        else pin_release<={pin_release[2:0],1'b1};
    always_ff @(posedge clk) local_release<={local_release[0],pin_release[1]};
    assign local_reset_n=local_release[1];
endmodule
