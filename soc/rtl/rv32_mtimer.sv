`timescale 1ns/1ps
// Single-hart timer subset of the proposed CLINT region. One mtime tick/clk.
// Software must use the usual RV32 high/low retry and safe mtimecmp write sequence.
module rv32_mtimer (
    input logic clk,reset_n,
    input logic write,
    input logic [31:0] address,write_data,
    input logic [3:0] write_mask,
    output logic selected,
    output logic [31:0] read_data,
    output wire timer_irq,
    output logic [63:0] mtime
);
    logic [63:0] mtimecmp;
    function automatic logic [31:0] merge(input logic [31:0] old_value,new_value,input logic [3:0] mask);
        logic [31:0] result;
        result=old_value;
        for(int b=0;b<4;b++) if(mask[b]) result[b*8+:8]=new_value[b*8+:8];
        return result;
    endfunction
    always_comb begin
        selected=1;
        case(address)
            32'h02004000: read_data=mtimecmp[31:0];
            32'h02004004: read_data=mtimecmp[63:32];
            32'h0200bff8: read_data=mtime[31:0];
            32'h0200bffc: read_data=mtime[63:32];
            default: begin read_data=0; selected=0; end
        endcase
    end
    assign timer_irq=reset_n && mtime>=mtimecmp;
    always_ff @(posedge clk) begin
        if(!reset_n) begin mtime<=0; mtimecmp<='1; end
        else begin
            mtime<=mtime+1'b1;
            if(write) case(address)
                32'h02004000: mtimecmp[31:0]<=merge(mtimecmp[31:0],write_data,write_mask);
                32'h02004004: mtimecmp[63:32]<=merge(mtimecmp[63:32],write_data,write_mask);
                32'h0200bff8: mtime<={mtime[63:32],merge(mtime[31:0],write_data,write_mask)};
                32'h0200bffc: mtime<={merge(mtime[63:32],write_data,write_mask),mtime[31:0]};
                default: begin end
            endcase
        end
    end
endmodule
