// Small synthesis check with real clocked reset sources, not unconstrained ports.
module xpm_synth_harness #(parameter int WIDTH=99)(
    input wire s_clk,d_clk,reset_n,s_valid,d_ready,
    input wire [WIDTH-1:0] s_data,
    output wire s_ready,d_valid,
    output wire [WIDTH-1:0] d_data
);
    wire sr,dr;
    reviewed_cpu_reset cpu_reset(.clk(s_clk),.reset_n,.local_reset_n(sr));
    or_bo_reset_sync fabric_reset(.clk(d_clk),.reset_n,.local_reset_n(dr));
    or_bo_xpm_mailbox #(.WIDTH(WIDTH)) crossing(
        .reset_n,.s_clk,.s_reset_n(sr),.d_clk,.d_reset_n(dr),
        .s_data,.s_valid,.s_ready,.d_data,.d_valid,.d_ready);
endmodule
