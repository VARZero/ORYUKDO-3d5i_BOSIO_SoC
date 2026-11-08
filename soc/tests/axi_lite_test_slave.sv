module axi_lite_test_slave #(parameter int ID=1)(
    input wire clk,reset_n,input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp
);
    logic aw,w,bv,rv;logic [31:0] value,data;logic [3:0] strb;int cycles;
    always_comb begin
        rsp='0;rsp.awready=reset_n && !aw && !bv && cycles%3!=0;
        rsp.wready=reset_n && !w && !bv && cycles%4!=0;
        rsp.arready=reset_n && !rv && cycles%5!=0;
        rsp.rvalid=rv;rsp.rdata=value;rsp.bvalid=bv;
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin aw<=0;w<=0;bv<=0;rv<=0;value<=32'hface0000+ID;data<=0;strb<=0;cycles<=0;end
        else begin
            cycles<=cycles+1;
            if(req.awvalid && rsp.awready) aw<=1;
            if(req.wvalid && rsp.wready) begin w<=1;data<=req.wdata;strb<=req.wstrb;end
            if(aw && w && !bv) begin
                for(int n=0;n<4;n++) if(strb[n]) value[n*8+:8]<=data[n*8+:8];
                aw<=0;w<=0;bv<=1;
            end
            if(bv && req.bready) bv<=0;
            if(req.arvalid && rsp.arready) rv<=1;
            if(rv && req.rready) rv<=0;
        end
    end
endmodule
