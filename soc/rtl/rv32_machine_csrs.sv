`timescale 1ns/1ps
// Ordered M/S/U privileged state. Architectural writes occur at retirement.
module rv32_machine_csrs (
    input logic clk,reset_n,flush,
    input logic [31:0] reset_mtvec,
    input logic timer_irq,
    input logic [63:0] time_value,
    input logic issue,
    input logic [36:0] issue_token,
    input logic [7:0] uop,
    input logic [31:0] instruction,operand,pc,
    output logic [31:0] read_value,next_pc,
    output logic illegal,
    input logic [2:0] retire_count,
    input logic retire,
    input logic [36:0] retire_token,
    input logic trap,trap_interrupt,
    input logic [31:0] trap_pc,trap_value,
    input logic [4:0] trap_cause,
    output wire interrupt_request,
    output wire [4:0] interrupt_cause,
    output wire [31:0] trap_vector,
    output logic [1:0] privilege,
    output wire [1:0] data_privilege,
    output logic [31:0] satp,
    output wire sum,mxr
);
    import rv32_pkg::*;
    localparam logic [31:0] STATUS_MASK=32'h007e19aa, SSTATUS_MASK=32'h000c0122;
    localparam logic [31:0] DELEG_MASK=32'h0000b3ff, IRQ_MASK=32'h000000a2;
    logic [31:0] status,mie,mideleg,medeleg,software_pending,mcounteren,scounteren;
    logic [31:0] mtvec,mscratch,mepc,mcause,mtval,stvec,sscratch,sepc,scause,stval;
    logic [63:0] mcycle,minstret;
    logic [2:0] inhibit;
    wire [31:0] mip=software_pending | (timer_irq?32'h80:0);
    logic boot_pending,pending,pending_write;
    logic [7:0] pending_uop;
    logic [36:0] pending_token;
    logic [11:0] pending_address;
    logic [31:0] pending_value;
    wire commit=pending && retire && retire_token==pending_token;
    wire [11:0] address=instruction[31:20];
    wire [2:0] operation=instruction[14:12];
    wire [31:0] source=operation[2]?{27'b0,instruction[19:15]}:operand;
    wire write_attempt=operation[1:0]==1 || instruction[19:15]!=0;
    logic [31:0] write_value;
    logic exists,counter_allowed,irq_available;
    logic [4:0] selected_irq;
    wire delegated=privilege!=3 && (trap_interrupt?mideleg[trap_cause]:medeleg[trap_cause]);
    wire [31:0] vector=delegated?stvec:mtvec;
    assign trap_vector={vector[31:2],2'b00}+((trap_interrupt && vector[1:0]==1)?{25'b0,trap_cause,2'b0}:0);
    assign data_privilege=status[17]?status[12:11]:privilege;
    assign sum=status[18];
    assign mxr=status[19];
    function automatic logic [31:0] legal_status(input logic [31:0] value);
        logic [31:0] result;
        result=value & STATUS_MASK;
        if(result[12:11]==2) result[12:11]=0;
        return result;
    endfunction
    always_comb begin
        read_value=0; exists=1; counter_allowed=1;
        case(address)
            12'h100: read_value=status&SSTATUS_MASK;
            12'h104: read_value=mie&mideleg;
            12'h105: read_value=stvec;
            12'h106: read_value=scounteren;
            12'h140: read_value=sscratch;
            12'h141: read_value=sepc;
            12'h142: read_value=scause;
            12'h143: read_value=stval;
            12'h144: read_value=mip&mideleg;
            12'h180: read_value=satp;
            12'h300: read_value=status;
            12'h301: read_value=32'h40141101;
            12'h302: read_value=medeleg;
            12'h303: read_value=mideleg;
            12'h304: read_value=mie;
            12'h305: read_value=mtvec;
            12'h306: read_value=mcounteren;
            12'h310: read_value=0;
            12'h320: read_value={29'b0,inhibit};
            12'h340: read_value=mscratch;
            12'h341: read_value=mepc;
            12'h342: read_value=mcause;
            12'h343: read_value=mtval;
            12'h344: read_value=mip;
            12'hb00,12'hc00: read_value=mcycle[31:0];
            12'hb80,12'hc80: read_value=mcycle[63:32];
            12'hb02,12'hc02: read_value=minstret[31:0];
            12'hb82,12'hc82: read_value=minstret[63:32];
            12'hc01: read_value=time_value[31:0];
            12'hc81: read_value=time_value[63:32];
            12'hf11,12'hf12,12'hf13,12'hf14: read_value=0;
            default: exists=0;
        endcase
        if(address[11:8]==4'hc && address[6:0]<=2 && privilege!=3)
            counter_allowed=mcounteren[{3'b0,address[1:0]}] && (privilege!=0 || scounteren[{3'b0,address[1:0]}]);
        case(operation[1:0])
            1: write_value=source;
            2: write_value=read_value|source;
            3: write_value=read_value&~source;
            default: write_value=0;
        endcase
        illegal=0;
        if(uop==U_CSR) illegal=!exists || privilege<address[9:8] || !counter_allowed ||
            (write_attempt && address[11:10]==3) || (address==12'h180 && privilege==1 && status[20]);
        if(uop==U_MRET) illegal=privilege!=3;
        if(uop==U_SRET) illegal=privilege==0 || (privilege==1 && status[22]);
        if(uop==U_SFENCE) illegal=privilege==0 || (privilege==1 && status[20]);
        // WFI completes immediately; TW permits completion within bounded time.
        if(uop==U_WFI) illegal=privilege==0;
        next_pc=uop==U_MRET?mepc:uop==U_SRET?sepc:pc+4;
        if(uop!=U_CSR) read_value=0;
    end
    always_comb begin
        irq_available=0; selected_irq=0;
        // All M-target interrupts outrank all S-target interrupts, regardless
        // of the cause number. Within each target: MTIP > STIP > SSIP.
        for(int target=0;target<2;target++) begin
            for(int n=0;n<3;n++) begin
                int c;
                c=n==0?1:n==1?5:7;
                if(mideleg[c]==(target==0) && mie[c] && mip[c] && (mideleg[c]?
                    (privilege==0 || (privilege==1 && status[1])):(privilege!=3 || status[3]))) begin
                    irq_available=1; selected_irq=5'(c);
                end
            end
        end
    end
    assign interrupt_cause=selected_irq;
    assign interrupt_request=reset_n && !boot_pending && !pending && irq_available;
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            privilege<=3; status<=32'h1800; satp<=0;
            mie<=0; mideleg<=0; medeleg<=0; software_pending<=0; mcounteren<=0; scounteren<=0;
            mtvec<=0; mscratch<=0; mepc<=0; mcause<=0; mtval<=0;
            stvec<=0; sscratch<=0; sepc<=0; scause<=0; stval<=0;
            mcycle<=0; minstret<=0; inhibit<=0; 
            pending<=0; pending_write<=0; pending_uop<=0; pending_token<=0;
            pending_address<=0; pending_value<=0; boot_pending<=1;
        end else begin
            
            if(!inhibit[0]) mcycle<=mcycle+1'b1;
            if(!inhibit[2]) minstret<=minstret+64'(retire_count);
            if(boot_pending) begin mtvec<={reset_mtvec[31:2],2'b00}; boot_pending<=0; end
            if(issue && !illegal) begin
                pending<=1; pending_token<=issue_token; pending_address<=address; pending_uop<=uop;
                pending_value<=write_value; pending_write<=uop==U_CSR && write_attempt;
            end
            if(commit) begin
                pending<=0;
                if(pending_uop==U_MRET) begin
                    privilege<=status[12:11]; status[3]<=status[7]; status[7]<=1; status[12:11]<=0;
                    if(status[12:11]!=3) status[17]<=0;
                end
                if(pending_uop==U_SRET) begin
                    privilege<=status[8]?2'd1:2'd0; status[1]<=status[5]; status[5]<=1; status[8]<=0; status[17]<=0;
                end
                if(pending_write) case(pending_address)
                    12'h100: status<=(status&~SSTATUS_MASK)|(pending_value&SSTATUS_MASK);
                    12'h104: mie<=(mie&~mideleg)|(pending_value&mideleg);
                    12'h105: stvec<={pending_value[31:2],1'b0,pending_value[1:0]==1};
                    12'h106: scounteren<=pending_value&7;
                    12'h140: sscratch<=pending_value;
                    12'h141: sepc<={pending_value[31:2],2'b0};
                    12'h142: scause<=pending_value;
                    12'h143: stval<=pending_value;
                    12'h144: software_pending<=(software_pending&~(mideleg&2))|(pending_value&mideleg&2);
                    12'h180: satp<={pending_value[31],9'b0,pending_value[21:0]};
                    12'h300: status<=legal_status(pending_value);
                    12'h302: medeleg<=pending_value&DELEG_MASK;
                    12'h303: mideleg<=pending_value&32'h22;
                    12'h304: mie<=pending_value&IRQ_MASK;
                    12'h305: mtvec<={pending_value[31:2],1'b0,pending_value[1:0]==1};
                    12'h306: mcounteren<=pending_value&7;
                    12'h320: inhibit<=pending_value[2:0]&3'b101;
                    12'h340: mscratch<=pending_value;
                    12'h341: mepc<={pending_value[31:2],2'b00};
                    12'h342: mcause<=pending_value;
                    12'h343: mtval<=pending_value;
                    12'h344: software_pending<=pending_value&32'h22;
                    12'hb00: mcycle<={mcycle[63:32],pending_value};
                    12'hb80: mcycle<={pending_value,mcycle[31:0]};
                    12'hb02: minstret<={minstret[63:32],pending_value};
                    12'hb82: minstret<={pending_value,minstret[31:0]};
                    default: begin end
                endcase
            end
            if(flush) pending<=0;
            if(trap) begin
                if(delegated) begin
                    sepc<={trap_pc[31:2],2'b0}; scause<={trap_interrupt,26'b0,trap_cause};
                    stval<=trap_interrupt?0:trap_value;
                    status[5]<=status[1]; status[1]<=0; status[8]<=privilege==1; privilege<=1;
                end else begin
                    mepc<={trap_pc[31:2],2'b0}; mcause<={trap_interrupt,26'b0,trap_cause};
                    mtval<=trap_interrupt?0:trap_value;
                    status[7]<=status[3]; status[3]<=0; status[12:11]<=privilege; privilege<=3;
                end
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        if(issue) assert(!pending) else $fatal(1,"Overlapping ordered CSR transactions");
        if(commit) assert(!flush) else $fatal(1,"CSR retirement overlaps flush");
    end
    // synthesis translate_on
endmodule
