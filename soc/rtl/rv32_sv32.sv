`timescale 1ns/1ps
// Sv32 walker with a small direct-mapped successful-translation cache.
// Svade/software A/D; full context tags; all-entry SFENCE invalidation.
// Outstanding reads drain and restart from the root on invalidation.
module rv32_sv32 #(
    parameter logic [31:0] PT_BASE=32'h20000, PT_LIMIT=32'h30000,
    parameter int TLB_ENTRIES=8
) (
    input logic clk,reset_n,flush,
    input logic valid,
    output wire ready,
    input logic [31:0] virtual_address,satp,
    input logic [1:0] privilege,access_type, // 0=fetch, 1=load/LR, 2=store/SC/AMO
    input logic sum,mxr,
    output wire result_valid,
    input logic result_ready,
    output logic [31:0] physical_address,
    output logic fault,
    output logic [4:0] cause,
    output wire request_valid,
    input logic request_ready,
    output logic [31:0] request_address,
    input logic response_valid,
    output wire response_ready,
    input logic [31:0] response_data,
    input logic response_fault
);
    typedef enum logic [1:0] {IDLE,REQUEST,RESPONSE,DONE} state_t;
    state_t state;
    logic [31:0] va;
    logic [1:0] mode,kind;
    logic saved_sum,saved_mxr,level;
    localparam int INDEX_W=TLB_ENTRIES<=1?1:$clog2(TLB_ENTRIES);
    logic [TLB_ENTRIES-1:0] cache_valid;
    logic [19:0] cache_vpn[TLB_ENTRIES],cache_ppn[TLB_ENTRIES];
    logic [31:0] cache_satp[TLB_ENTRIES],saved_satp;
    logic [5:0] cache_context[TLB_ENTRIES];
    logic restart_walk;
    wire [INDEX_W-1:0] lookup_index=TLB_ENTRIES<=1?'0:virtual_address[12+:INDEX_W];
    wire [INDEX_W-1:0] fill_index=TLB_ENTRIES<=1?'0:va[12+:INDEX_W];
    wire [5:0] lookup_context={privilege,access_type,sum,mxr};
    wire cache_hit=cache_valid[lookup_index] && !flush &&
        cache_vpn[lookup_index]==virtual_address[31:12] && cache_satp[lookup_index]==satp &&
        cache_context[lookup_index]==lookup_context;
    wire [31:0] saved_root={saved_satp[19:0],12'b0}+{20'b0,va[31:22],2'b0};
    wire [4:0] page_cause=kind==0?5'd12:kind==1?5'd13:5'd15;
    wire [4:0] access_cause=kind==0?5'd1:kind==1?5'd5:5'd7;
    wire [31:0] pte=response_data;
    wire leaf=pte[1] || pte[3];
    wire permission=(kind==0?pte[3]:kind==1?(pte[1] || (saved_mxr && pte[3])):pte[2]) &&
        (mode==0?pte[4]:(!pte[4] || (kind!=0 && saved_sum)));
    wire [31:0] next_table={pte[29:10],12'b0}+{20'b0,va[21:12],2'b0};
    wire [31:0] root_address={satp[19:0],12'b0}+{20'b0,virtual_address[31:22],2'b0};
    assign ready=reset_n && state==IDLE;
    assign result_valid=state==DONE && !flush;
    assign request_valid=state==REQUEST;
    assign response_ready=state==RESPONSE;
    always_ff @(posedge clk) begin
        if(!reset_n) begin
            state<=IDLE; va<=0; mode<=3; kind<=0; saved_sum<=0; saved_mxr<=0; level<=1;
            physical_address<=0; fault<=0; cause<=0; request_address<=0;
            cache_valid<='0;saved_satp<=0;restart_walk<=0;
        end else begin
          case(state)
            IDLE: if(valid) begin
                va<=virtual_address; saved_satp<=satp;restart_walk<=0;mode<=privilege; kind<=access_type; saved_sum<=sum; saved_mxr<=mxr;
                fault<=0; cause<=0; level<=1; physical_address<=virtual_address;
                if(privilege==3 || !satp[31]) state<=DONE;
                else if(satp[21:20]!=0 || root_address<PT_BASE || root_address>=PT_LIMIT) begin
                    fault<=1; cause<=access_type==0?5'd1:access_type==1?5'd5:5'd7; state<=DONE;
                end else if(cache_hit) begin
                    physical_address<={cache_ppn[lookup_index],virtual_address[11:0]};state<=DONE;
                end else begin request_address<=root_address; state<=REQUEST; end
            end
            REQUEST: if(request_ready) state<=RESPONSE;
            RESPONSE: if(response_valid) begin
                state<=DONE; fault<=1; cause<=page_cause;
                if(flush || restart_walk) begin
                    request_address<=saved_root;level<=1;fault<=0;state<=REQUEST;restart_walk<=0;
                end else if(response_fault) cause<=access_cause;
                else if(!pte[0] || (!pte[1] && pte[2])) begin end
                else if(leaf) begin
                    if(!permission || (level && pte[19:10]!=0) || !pte[6] || (kind==2 && !pte[7])) begin end
                    else if(pte[31:30]!=0) cause<=access_cause; // 34-bit PA must never silently alias.
                    else begin
                        physical_address<=level?{pte[29:20],va[21:0]}:{pte[29:10],va[11:0]};
                        fault<=0;
                        cache_valid[fill_index]<=1;
                        cache_vpn[fill_index]<=va[31:12];cache_satp[fill_index]<=saved_satp;
                        cache_context[fill_index]<={mode,kind,saved_sum,saved_mxr};
                        cache_ppn[fill_index]<=level?{pte[29:20],va[21:12]}:pte[29:10];
                    end
                end else if(!level || pte[7] || pte[6] || pte[4]) begin end
                else if(pte[31:30]!=0 || next_table<PT_BASE || next_table>=PT_LIMIT) cause<=access_cause;
                else begin request_address<=next_table; level<=0; fault<=0; state<=REQUEST; end
            end
            DONE: if(flush && mode!=3 && saved_satp[31] && saved_satp[21:20]==0 && saved_root>=PT_BASE && saved_root<PT_LIMIT) begin
                request_address<=saved_root;level<=1;fault<=0;state<=REQUEST;restart_walk<=0;
            end else if(result_ready && !flush) state<=IDLE;
            default: state<=IDLE;
          endcase
          if(flush) begin
              cache_valid<='0;
              if(state==REQUEST || (state==RESPONSE && !response_valid)) restart_walk<=1;
          end
        end
    end
    initial begin
        assert(TLB_ENTRIES>0 && (TLB_ENTRIES & (TLB_ENTRIES-1))==0)
            else $fatal(1,"TLB_ENTRIES must be a positive power of two");
    end
endmodule
