`timescale 1ns/1ps
package rv32_pkg;
    typedef enum logic [7:0] {
        U_ADD=8'h00, U_SUB=8'h01, U_SLL=8'h02, U_SLT=8'h03,
        U_SLTU=8'h04, U_XOR=8'h05, U_SRL=8'h06, U_SRA=8'h07,
        U_OR=8'h08, U_AND=8'h09,
        U_ADDI=8'h10, U_SLLI=8'h12, U_SLTI=8'h13, U_SLTIU=8'h14,
        U_XORI=8'h15, U_SRLI=8'h16, U_SRAI=8'h17, U_ORI=8'h18, U_ANDI=8'h19,
        U_LUI=8'h20, U_AUIPC=8'h21,
        U_JAL=8'h30, U_JALR=8'h31, U_BEQ=8'h32, U_BNE=8'h33,
        U_BLT=8'h34, U_BGE=8'h35, U_BLTU=8'h36, U_BGEU=8'h37, U_FENCE=8'h38,
        U_LB=8'h40, U_LH=8'h41, U_LW=8'h42, U_LBU=8'h44, U_LHU=8'h45,
        U_SB=8'h48, U_SH=8'h49, U_SW=8'h4a,
        U_MUL=8'h50, U_MULH=8'h51, U_MULHSU=8'h52, U_MULHU=8'h53,
        U_DIV=8'h54, U_DIVU=8'h55, U_REM=8'h56, U_REMU=8'h57,
        U_CSR=8'h60, U_MRET=8'h61, U_WFI=8'h62, U_SRET=8'h63, U_SFENCE=8'h64,
        U_LR=8'h70, U_SC=8'h71, U_AMOSWAP=8'h72, U_AMOADD=8'h73,
        U_AMOXOR=8'h74, U_AMOAND=8'h75, U_AMOOR=8'h76,
        U_AMOMIN=8'h77, U_AMOMAX=8'h78, U_AMOMINU=8'h79, U_AMOMAXU=8'h7a
    } uop_t;
    function automatic logic is_atomic(input logic [7:0] uop);
        return uop>=U_LR && uop<=U_AMOMAXU;
    endfunction

    // LSQ returns aligned raw words (including byte forwarding). Extend at RF writeback.
    function automatic logic [31:0] load_value(input logic [7:0] uop,
        input logic [31:0] word_data, input logic [1:0] offset);
        logic [31:0] shifted;
        shifted=word_data >> {offset,3'b000};
        case (uop)
            U_LB: return {{24{shifted[7]}},shifted[7:0]};
            U_LH: return {{16{shifted[15]}},shifted[15:0]};
            U_LW: return shifted;
            U_LBU: return {24'b0,shifted[7:0]};
            U_LHU: return {16'b0,shifted[15:0]};
            default: return word_data;
        endcase
    endfunction
endpackage
