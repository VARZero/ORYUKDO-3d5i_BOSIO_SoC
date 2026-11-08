`timescale 1ns/1ps
module rv32_decode (
    input logic [31:0] instruction,
    output logic [1:0] path,
    output logic [7:0] uop,
    output logic [31:0] immediate,
    output logic [4:0] rd, rs1, rs2,
    output logic writes, control, memory_op, store_op, serial_op,
    output logic exception,
    output logic [4:0] cause
);
    import rv32_pkg::*;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    always_comb begin
        opcode=instruction[6:0]; funct3=instruction[14:12]; funct7=instruction[31:25];
        path=1; uop=U_ADD; immediate=0;
        rd=instruction[11:7]; rs1=0; rs2=0;
        writes=0; control=0; memory_op=0; store_op=0; serial_op=0;
        exception=0; cause=2;
        case(opcode)
            7'h37,7'h17: begin
                writes=1; immediate={instruction[31:12],12'b0};
                uop=(opcode==7'h37)?U_LUI:U_AUIPC;
            end
            7'h13: begin
                writes=1; rs1=instruction[19:15]; immediate={{20{instruction[31]}},instruction[31:20]};
                case(funct3)
                    0: uop=U_ADDI;
                    2: uop=U_SLTI;
                    3: uop=U_SLTIU;
                    4: uop=U_XORI;
                    6: uop=U_ORI;
                    7: uop=U_ANDI;
                    1: begin uop=U_SLLI; exception=funct7!=0; end
                    5: begin uop=instruction[30]?U_SRAI:U_SRLI; exception=funct7!=0 && funct7!=7'h20; end
                    default: exception=1;
                endcase
            end
            7'h33: begin
                writes=1; rs1=instruction[19:15]; rs2=instruction[24:20];
                if(funct7==1) begin path=2; uop=8'h50+{5'b0,funct3}; end
                else begin
                    case(funct3)
                        0: begin uop=instruction[30]?U_SUB:U_ADD; exception=funct7!=0 && funct7!=7'h20; end
                        1: begin uop=U_SLL; exception=funct7!=0; end
                        2: begin uop=U_SLT; exception=funct7!=0; end
                        3: begin uop=U_SLTU; exception=funct7!=0; end
                        4: begin uop=U_XOR; exception=funct7!=0; end
                        5: begin uop=instruction[30]?U_SRA:U_SRL; exception=funct7!=0 && funct7!=7'h20; end
                        6: begin uop=U_OR; exception=funct7!=0; end
                        7: begin uop=U_AND; exception=funct7!=0; end
                        default: exception=1;
                    endcase
                end
            end
            7'h6f: begin
                path=0; writes=1; control=1; uop=U_JAL;
                immediate={{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
            end
            7'h67: begin
                path=0; writes=1; control=1; uop=U_JALR; rs1=instruction[19:15];
                immediate={{20{instruction[31]}},instruction[31:20]}; exception=funct3!=0;
            end
            7'h63: begin
                path=0; control=1; rs1=instruction[19:15]; rs2=instruction[24:20];
                immediate={{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
                case(funct3)
                    0: uop=U_BEQ;
                    1: uop=U_BNE;
                    4: uop=U_BLT;
                    5: uop=U_BGE;
                    6: uop=U_BLTU;
                    7: uop=U_BGEU;
                    default: exception=1;
                endcase
            end
            7'h03: begin
                path=3; memory_op=1; writes=1; rs1=instruction[19:15];
                immediate={{20{instruction[31]}},instruction[31:20]};
                case(funct3)
                    0: uop=U_LB;
                    1: uop=U_LH;
                    2: uop=U_LW;
                    4: uop=U_LBU;
                    5: uop=U_LHU;
                    default: exception=1;
                endcase
            end
            7'h23: begin
                path=3; memory_op=1; store_op=1; rs1=instruction[19:15]; rs2=instruction[24:20];
                immediate={{20{instruction[31]}},instruction[31:25],instruction[11:7]};
                case(funct3)
                    0: uop=U_SB;
                    1: uop=U_SH;
                    2: uop=U_SW;
                    default: exception=1;
                endcase
            end
            7'h2f: begin
                // Reuse the scheduler's ordered-head barrier on the memory lane.
                // Atomic requests bypass the ordinary LSQ and complete via EX.
                path=3; writes=1; serial_op=1; immediate=instruction;
                rs1=instruction[19:15]; rs2=instruction[24:20];
                exception=funct3!=2;
                case(instruction[31:27])
                    5'b00010: begin uop=U_LR; if(rs2!=0) exception=1; end
                    5'b00011: uop=U_SC;
                    5'b00001: uop=U_AMOSWAP;
                    5'b00000: uop=U_AMOADD;
                    5'b00100: uop=U_AMOXOR;
                    5'b01100: uop=U_AMOAND;
                    5'b01000: uop=U_AMOOR;
                    5'b10000: uop=U_AMOMIN;
                    5'b10100: uop=U_AMOMAX;
                    5'b11000: uop=U_AMOMINU;
                    5'b11100: uop=U_AMOMAXU;
                    default: exception=1;
                endcase
            end
            7'h0f: begin
                // No caches yet. Both fences serialize through the ordered system path;
                // the scheduler changes fetch epoch at retirement, discarding prefetched data.
                path=0; serial_op=1; uop=U_FENCE; exception=funct3!=0 && funct3!=1;
            end
            7'h73: begin
                path=0; immediate=instruction;
                if(funct3==1 || funct3==2 || funct3==3 || funct3==5 || funct3==6 || funct3==7) begin
                    uop=U_CSR; serial_op=1; writes=1;
                    // Preserve the architectural rs1 field in immediate even when
                    // its value is zero: CSRRS xN=0 still attempts a CSR write.
                    if(!funct3[2]) rs1=instruction[19:15];
                end else if(instruction==32'h30200073) begin
                    uop=U_MRET; serial_op=1; control=1;
                end else if(instruction==32'h10200073) begin
                    uop=U_SRET; serial_op=1; control=1;
                end else if((instruction & 32'hfe007fff)==32'h12000073) begin
                    uop=U_SFENCE; serial_op=1; // No TLB: ordered drain + fetch epoch is a full fence.
                end else if(instruction==32'h10500073) begin
                    uop=U_WFI; serial_op=1; // Legal non-stalling WFI implementation.
                end else begin
                    exception=1;
                    if(instruction==32'h00000073) cause=11;
                    else if(instruction==32'h00100073) cause=3;
                end
            end
            default: exception=1;
        endcase
        if(!writes) rd=0;
        if(exception) begin
            writes=0; control=0; memory_op=0; store_op=0; serial_op=0; rd=0; rs1=0; rs2=0;
        end
    end
endmodule
