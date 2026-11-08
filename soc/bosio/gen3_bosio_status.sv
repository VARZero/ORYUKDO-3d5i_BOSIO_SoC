module gen3_bosio_status(
    input wire clk,reset_n,input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp,
    output logic sensor_enable,input wire sensor_ready,sensor_error,input wire [1:0] projection_irq
);
    import or_bo_axi_pkg::*;
    logic aw_pending,w_pending,bvalid,rvalid;
    logic [4:0] address;logic [31:0] data,rdata;logic [3:0] strb;logic [1:0] bresp,rresp,sticky;
    always_comb begin
        rsp='0;rsp.awready=reset_n && !aw_pending && !bvalid;rsp.wready=reset_n && !w_pending && !bvalid;
        rsp.bvalid=bvalid;rsp.bresp=bresp;rsp.arready=reset_n && !rvalid;rsp.rvalid=rvalid;rsp.rdata=rdata;rsp.rresp=rresp;
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin aw_pending<=0;w_pending<=0;bvalid<=0;rvalid<=0;sensor_enable<=0;sticky<=0;address<=0;data<=0;strb<=0;bresp<=0;rresp<=0;rdata<=0;end
        else begin
            sticky<=sticky|projection_irq;
            if(req.awvalid && rsp.awready) begin aw_pending<=1;address<=req.awaddr[4:0];end
            if(req.wvalid && rsp.wready) begin w_pending<=1;data<=req.wdata;strb<=req.wstrb;end
            if(aw_pending && w_pending) begin
                aw_pending<=0;w_pending<=0;bvalid<=1;bresp<=OKAY;
                case(address)
                    0: if(strb[0]) sensor_enable<=data[0];
                    16: if(strb[0]) sticky<=(sticky&~data[1:0])|projection_irq;
                    default:bresp<=SLVERR;
                endcase
            end
            if(bvalid && req.bready) bvalid<=0;
            if(req.arvalid && rsp.arready) begin
                rvalid<=1;rresp<=OKAY;
                case(req.araddr[4:0])
                    0:rdata<={31'b0,sensor_enable};
                    4:rdata<={30'b0,sensor_error,sensor_ready};
                    8:rdata<=32'h41584931;
                    16:rdata<={30'b0,sticky};
                    default:begin rdata<=0;rresp<=SLVERR;end
                endcase
            end
            if(rvalid && req.rready) rvalid<=0;
        end
    end
endmodule
