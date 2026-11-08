// Independent one-entry AW, W and AR queues. Register side effects occur once,
// before the response; response payloads are held through AXI backpressure.
module gen3_axil_regs(
    input wire clk,reset_n,
    input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp,
    output wire valid,store,output wire [31:0] address,write_data,
    output wire [3:0] mask,input wire ready,error,input wire [31:0] read_data
);
    logic ap,wp,rp,bv,rv;logic [31:0] aa,ra,wd,rd;logic [3:0] ws,rm;
    logic [1:0] br,rr;
    wire wr=ap && wp && !bv;
    assign valid=reset_n && (wr || (rp && !rv));
    assign store=wr;assign address=wr?aa:ra;assign write_data=wd;assign mask=wr?ws:rm;
    always_comb begin
        rsp='0;rsp.awready=reset_n && !ap && !bv;rsp.wready=reset_n && !wp && !bv;
        rsp.arready=reset_n && !rp && !rv;rsp.bvalid=bv;rsp.bresp=br;
        rsp.rvalid=rv;rsp.rresp=rr;rsp.rdata=rd;
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin ap<=0;wp<=0;rp<=0;bv<=0;rv<=0;aa<=0;ra<=0;wd<=0;rd<=0;ws<=0;rm<=0;br<=0;rr<=0;end
        else begin
            if(req.awvalid && rsp.awready) begin ap<=1;aa<=req.awaddr;end
            if(req.wvalid && rsp.wready) begin wp<=1;wd<=req.wdata;ws<=req.wstrb;end
            if(req.arvalid && rsp.arready) begin rp<=1;ra<=req.araddr;rm<=req.rmask;end
            if(bv && req.bready) bv<=0;
            if(rv && req.rready) rv<=0;
            if(valid && ready) begin
                if(store) begin ap<=0;wp<=0;bv<=1;br<=error?2'b10:2'b00;end
                else begin rp<=0;rv<=1;rd<=read_data;rr<=error?2'b10:2'b00;end
            end
        end
    end
endmodule

module gen3_axi_uart(
    input wire clk,reset_n,rx,output wire tx,
    input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp
);
    wire valid,store,ready;wire [31:0] address,write_data,read_data;wire [3:0] mask;
    gen3_axil_regs bus(.clk,.reset_n,.req,.rsp,.valid,.store,.ready,.address,.write_data,.read_data,.mask,.error(1'b0));
    // 100 MHz / (16 * 54) = 115740.7 baud by default, programmable divisor.
    uart8250_poll #(.RESET_DIVISOR(16'd54)) uart(.clk,.reset_n,.valid,.store,.address(address[2:0]),.write_data,.mask,.ready,.read_data,.rx,.tx);
endmodule
