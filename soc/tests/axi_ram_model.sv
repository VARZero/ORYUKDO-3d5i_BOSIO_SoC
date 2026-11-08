`timescale 1ns/1ps
module axi_ram_model #(parameter int WORDS=131072)(
    input wire clk,reset_n,input or_bo_axi_pkg::ax_req_t req,output or_bo_axi_pkg::ax_rsp_t rsp
);
    import or_bo_axi_pkg::*;
    logic [31:0] mem[WORDS];
    ax_addr_t rd,wr;
    logic reading,writing,bvalid,rvalid;
    ax_r_t r;ax_b_t b;
    logic [7:0] ri,wi;
    int cycles,reads,writes,seed=1;
    wire [63:0] ra=rd.addr+(rd.burst==1?{54'b0,ri,2'b0}:64'b0);
    wire [63:0] wa=wr.addr+(wr.burst==1?{54'b0,wi,2'b0}:64'b0);
    wire rok=ra>=64'h80000000 && ra<64'h80000000+WORDS*4;
    wire wok=wa>=64'h80000000 && wa<64'h80000000+WORDS*4;
    string image_name;
    initial begin
        for(int n=0;n<WORDS;n++) mem[n]=0;
        `ifndef VERILATOR
        #1;
        `endif
        if($value$plusargs("image=%s",image_name)) $readmemh(image_name,mem);
        if($value$plusargs("seed=%d",seed)) begin end
    end
    always_comb begin
        rsp='0;
        // Deliberately vary stalls independently on all channels.
        rsp.arready=reset_n && !reading && !rvalid && (cycles+seed)%5!=0;
        rsp.awready=reset_n && !writing && !bvalid && (cycles+seed)%4!=0;
        rsp.wready=reset_n && writing && (cycles+seed)%3!=0;
        rsp.rvalid=rvalid;rsp.r=r;rsp.bvalid=bvalid;rsp.b=b;
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin reading<=0;writing<=0;bvalid<=0;rvalid<=0;rd<='0;wr<='0;r<='0;b<='0;ri<=0;wi<=0;cycles<=0;reads<=0;writes<=0;end
        else begin
            cycles<=cycles+1;
            if(req.arvalid && rsp.arready) begin rd<=req.ar;ri<=0;reading<=1;end
            if(req.awvalid && rsp.awready) begin wr<=req.aw;wi<=0;writing<=1;b.resp<=OKAY;b.id<=req.aw.id;end
            if(req.wvalid && rsp.wready) begin
                if(wok) begin
                    for(int n=0;n<4;n++) if(req.w.strb[n]) mem[(wa-64'h80000000)>>2][n*8+:8]<=req.w.data[n*8+:8];
                end
                else b.resp<=DECERR;
                assert(req.w.last==(wi==wr.len)) else $fatal(1,"RAM WLAST");
                writes<=writes+1;
                if(wi==wr.len) begin writing<=0;bvalid<=1;end else wi<=wi+1'b1;
            end
            if(bvalid && req.bready) bvalid<=0;
            if(reading && !rvalid && (cycles+seed)%4!=0) begin
                rvalid<=1;r.data<=rok?mem[(ra-64'h80000000)>>2]:0;r.resp<=rok?OKAY:DECERR;r.last<=ri==rd.len;r.id<=rd.id;r.user<=0;
            end
            if(rvalid && req.rready) begin
                rvalid<=0;reads<=reads+1;
                if(ri==rd.len) reading<=0;else ri<=ri+1'b1;
            end
        end
    end
endmodule
