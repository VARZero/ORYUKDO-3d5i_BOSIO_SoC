`timescale 1ns/1ps
// Lanes 1 and 2: integer ALU only. Branch/system operations are not supported.
module rv32_alu_execute (
    input logic [7:0] uop,
    input logic [31:0] pc, a, b, immediate,
    output logic [31:0] value, next_pc,
    output logic fault,
    output logic [4:0] cause
);
    import rv32_pkg::*;
    logic [31:0] rhs;
    always_comb begin
        rhs=uop[4]?immediate:b;
        value=0; next_pc=pc+4; fault=0; cause=0;
        case(uop)
            U_ADD,U_ADDI: value=a+rhs;
            U_SUB: value=a-b;
            U_SLL,U_SLLI: value=a<<rhs[4:0];
            U_SLT,U_SLTI: value={31'b0,$signed(a)<$signed(rhs)};
            U_SLTU,U_SLTIU: value={31'b0,a<rhs};
            U_XOR,U_XORI: value=a^rhs;
            U_SRL,U_SRLI: value=a>>rhs[4:0];
            U_SRA,U_SRAI: value=$signed(a)>>>rhs[4:0];
            U_OR,U_ORI: value=a|rhs;
            U_AND,U_ANDI: value=a&rhs;
            U_LUI: value=immediate;
            U_AUIPC: value=pc+immediate;
            default: begin fault=1; cause=2; end
        endcase
        if(next_pc[1:0]!=0) begin fault=1; cause=0; end
    end
endmodule

// Lane 0: branch/jump/fence only. The separate CSR unit handles system uops.
module rv32_branch_execute (
    input logic [7:0] uop,
    input logic [31:0] pc, a, b, immediate,
    output logic [31:0] value, next_pc,
    output logic fault,
    output logic [4:0] cause
);
    import rv32_pkg::*;
    logic take;
    always_comb begin
        value=0; next_pc=pc+4; fault=0; cause=0; take=0;
        case(uop)
            U_JAL: begin value=pc+4; take=1; end
            U_JALR: begin value=pc+4; next_pc=(a+immediate)&32'hfffffffe; end
            U_BEQ: take=a==b;
            U_BNE: take=a!=b;
            U_BLT: take=$signed(a)<$signed(b);
            U_BGE: take=$signed(a)>=$signed(b);
            U_BLTU: take=a<b;
            U_BGEU: take=a>=b;
            U_FENCE: begin end
            default: begin fault=1; cause=2; end
        endcase
        if(take) next_pc=pc+immediate;
        if(next_pc[1:0]!=0) begin fault=1; cause=0; end
    end
endmodule
