// Four-master, transaction-serialized AXI4 interconnect. RR arbitration is at
// transaction boundaries; bursts are never interleaved. CPU owns index zero.
// External RAM must answer accepted requests. No timeout can cancel AXI traffic.
module or_bo_axi_fabric (
    input wire clk,reset_n,
    input or_bo_axi_pkg::ax_req_t masters[4],output or_bo_axi_pkg::ax_rsp_t replies[4],
    output or_bo_axi_pkg::ax_req_t memory,input or_bo_axi_pkg::ax_rsp_t memory_reply,
    output or_bo_axi_pkg::al_req_t lite[or_bo_axi_pkg::LITE_PORTS],
    input or_bo_axi_pkg::al_rsp_t lite_reply[or_bo_axi_pkg::LITE_PORTS],
    input wire lock_request,output wire lock_grant,
    output wire snoop_valid,output wire [31:0] snoop_address,input wire snoop_ready,
    output wire [1:0] active_master,output wire busy
);
    import or_bo_axi_pkg::*;
    // RAM-facing control changes only on clk, including reset assertion.
    logic active=0;
    always_ff @(posedge clk) active<=reset_n;
    typedef enum logic [3:0] {IDLE,CHECK,RADDR,RDATA,WDATA,BRESP,ERR_READ,ERR_WRITE,ERR_B} state_t;
    state_t state;
    ax_addr_t saved;
    logic [1:0] owner,rr;
    logic prefer_write,aw_sent,w_finished,snoop_sent,snoop_request,bad_last,locked,saved_write;
    logic [7:0] beat;
    logic signed [3:0] destination;
    integer selected;
    logic selected_write;
    logic awready,wready,rvalid,bvalid;
    ax_r_t r;
    ax_b_t b;
    wire dma_write=owner!=0 && destination==7;
    wire snoop_complete=!dma_write || (snoop_sent && snoop_ready);
    // RAM write enable must not inherit the upstream CDC's asynchronous cancel.
    // Capture the request locally; hold it until the invalidate FIFO accepts it.
    assign snoop_valid=active && state==WDATA && dma_write && !snoop_sent && !w_finished && snoop_request;
    assign snoop_address=saved.addr[31:0]+(saved.burst==1?{22'b0,beat,2'b0}:32'b0);
    assign lock_grant=locked;
    assign busy=state!=IDLE;
    assign active_master=owner;
    always_comb begin
        selected=-1;selected_write=0;
        for(int n=0;n<4;n++) begin
            if(selected<0 && (!(locked || lock_request) || ((int'(rr)+n)%4)==0) &&
               (masters[(int'(rr)+n)%4].arvalid || masters[(int'(rr)+n)%4].awvalid)) begin
                selected=(int'(rr)+n)%4;
                selected_write=masters[selected].awvalid && (!masters[selected].arvalid || prefer_write);
            end
        end
        for(int n=0;n<4;n++) replies[n]='0;
        for(int n=0;n<LITE_PORTS;n++) lite[n]='0;
        memory='0;awready=0;wready=0;rvalid=0;bvalid=0;r='0;b='0;
        if(active) case(state)
            IDLE: if(selected>=0) begin
                if(selected_write) replies[selected].awready=1;
                else replies[selected].arready=1;
            end
            RADDR: begin
                if(destination==7) begin memory.ar=saved;memory.arvalid=1;end
                else begin lite[destination].araddr=saved.addr[31:0];lite[destination].arprot=saved.prot;lite[destination].rmask=saved.user;lite[destination].arvalid=1;end
            end
            RDATA: begin
                if(destination==7) begin memory.rready=masters[owner].rready;r=memory_reply.r;rvalid=memory_reply.rvalid;end
                else begin
                    lite[destination].rready=masters[owner].rready;
                    r.data=lite_reply[destination].rdata;r.resp=lite_reply[destination].rresp;r.last=1;
                    rvalid=lite_reply[destination].rvalid;
                end
                r.id=saved.id;r.user=0;
                replies[owner].r=r;replies[owner].rvalid=rvalid;
            end
            WDATA: begin
                if(destination==7) begin
                    memory.aw=saved;memory.awvalid=!aw_sent;
                    memory.w=masters[owner].w;
                    memory.wvalid=!w_finished && masters[owner].wvalid && snoop_complete;
                    awready=memory_reply.awready;wready=memory_reply.wready && snoop_complete;
                end else begin
                    lite[destination].awaddr=saved.addr[31:0];lite[destination].awprot=saved.prot;
                    lite[destination].awvalid=!aw_sent;
                    lite[destination].wdata=masters[owner].w.data;lite[destination].wstrb=masters[owner].w.strb;
                    lite[destination].wvalid=!w_finished && masters[owner].wvalid;
                    awready=lite_reply[destination].awready;wready=lite_reply[destination].wready;
                end
                replies[owner].wready=!w_finished && wready;
            end
            BRESP: begin
                if(destination==7) begin memory.bready=masters[owner].bready;b=memory_reply.b;bvalid=memory_reply.bvalid;end
                else begin lite[destination].bready=masters[owner].bready;b.resp=lite_reply[destination].bresp;bvalid=lite_reply[destination].bvalid;end
                b.id=saved.id;b.user=0;if(bad_last) b.resp=SLVERR;
                replies[owner].b=b;replies[owner].bvalid=bvalid;
            end
            ERR_READ: begin replies[owner].rvalid=1;replies[owner].r.id=saved.id;replies[owner].r.last=beat==saved.len;replies[owner].r.resp=DECERR;end
            ERR_WRITE: replies[owner].wready=1;
            ERR_B: begin replies[owner].bvalid=1;replies[owner].b.id=saved.id;replies[owner].b.resp=DECERR;end
            default:;
        endcase
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin state<=IDLE;saved<='0;owner<=0;rr<=0;beat<=0;prefer_write<=0;
            aw_sent<=0;w_finished<=0;snoop_sent<=0;snoop_request<=0;bad_last<=0;locked<=0;saved_write<=0;destination<=-1;end
        else if(active) begin
            if(state==IDLE) begin
                if(lock_request) locked<=1;
                else locked<=0;
            end
            case(state)
                IDLE: if(selected>=0) begin
                    owner<=2'(selected);rr<=2'(selected+1);prefer_write<=!selected_write;
                    beat<=0;aw_sent<=0;w_finished<=0;snoop_sent<=0;snoop_request<=0;bad_last<=0;
                    saved<=selected_write?masters[selected].aw:masters[selected].ar;
                    saved_write<=selected_write;state<=CHECK;
                end
                CHECK: begin
                    destination<=4'(target(saved.addr));
                    if(saved_write) state<=legal(saved,owner==0)?WDATA:ERR_WRITE;
                    else state<=legal(saved,owner==0)?RADDR:ERR_READ;
                end
                RADDR: if(destination==7?memory_reply.arready:lite_reply[destination].arready) state<=RDATA;
                RDATA: if(rvalid && masters[owner].rready) begin
                    if(beat==saved.len) state<=IDLE;else beat<=beat+1'b1;
                end
                WDATA: begin
                    if(!aw_sent && awready) aw_sent<=1;
                    if(dma_write && !snoop_sent && !w_finished && masters[owner].wvalid) snoop_request<=1;
                    if(snoop_valid && snoop_ready) begin snoop_sent<=1;snoop_request<=0;end
                    if(!w_finished && masters[owner].wvalid && wready) begin
                        snoop_sent<=0;snoop_request<=0;
                        if(masters[owner].w.last!=(beat==saved.len)) bad_last<=1;
                        if(beat==saved.len) w_finished<=1;else beat<=beat+1'b1;
                    end
                    if((aw_sent || awready) && (w_finished ||
                       (masters[owner].wvalid && wready && beat==saved.len))) state<=BRESP;
                end
                BRESP: if(bvalid && masters[owner].bready) state<=IDLE;
                ERR_READ: if(masters[owner].rready) begin if(beat==saved.len) state<=IDLE;else beat<=beat+1'b1;end
                ERR_WRITE: if(masters[owner].wvalid) begin if(beat==saved.len) state<=ERR_B;else beat<=beat+1'b1;end
                ERR_B: if(masters[owner].bready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        if(locked && state!=IDLE) assert(owner==0) else $fatal(1,"DMA during CPU atomic lock");
        if(state==RDATA && rvalid) assert(r.last==(beat==saved.len)) else $fatal(1,"Bad AXI RLAST");
    end
    // synthesis translate_on
endmodule
