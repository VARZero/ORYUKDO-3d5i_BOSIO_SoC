module or_bo_axi_cdc (
    input wire reset_n,s_clk,s_reset_n,m_clk,m_reset_n,
    input or_bo_axi_pkg::ax_req_t s_req,output or_bo_axi_pkg::ax_rsp_t s_rsp,
    output or_bo_axi_pkg::ax_req_t m_req,input or_bo_axi_pkg::ax_rsp_t m_rsp
);
    import or_bo_axi_pkg::*;
    or_bo_xpm_mailbox #(.WIDTH($bits(ax_addr_t)),.WAIT_CONSUMED(0)) aw(
        .reset_n,.s_clk(s_clk),.s_reset_n(s_reset_n),.d_clk(m_clk),.d_reset_n(m_reset_n),
        .s_data(s_req.aw),.s_valid(s_req.awvalid),.s_ready(s_rsp.awready),
        .d_data(m_req.aw),.d_valid(m_req.awvalid),.d_ready(m_rsp.awready));
    or_bo_xpm_mailbox #(.WIDTH($bits(ax_w_t)),.WAIT_CONSUMED(0)) w(
        .reset_n,.s_clk(s_clk),.s_reset_n(s_reset_n),.d_clk(m_clk),.d_reset_n(m_reset_n),
        .s_data(s_req.w),.s_valid(s_req.wvalid),.s_ready(s_rsp.wready),
        .d_data(m_req.w),.d_valid(m_req.wvalid),.d_ready(m_rsp.wready));
    or_bo_cdc_mailbox #(.WIDTH($bits(ax_b_t)),.SYNC_PAYLOAD(1'b1)) b(
        .s_clk(m_clk),.s_reset_n(m_reset_n),.d_clk(s_clk),.d_reset_n(s_reset_n),
        .s_data(m_rsp.b),.s_valid(m_rsp.bvalid),.s_ready(m_req.bready),
        .d_data(s_rsp.b),.d_valid(s_rsp.bvalid),.d_ready(s_req.bready));
    or_bo_xpm_mailbox #(.WIDTH($bits(ax_addr_t)),.WAIT_CONSUMED(0)) ar(
        .reset_n,.s_clk(s_clk),.s_reset_n(s_reset_n),.d_clk(m_clk),.d_reset_n(m_reset_n),
        .s_data(s_req.ar),.s_valid(s_req.arvalid),.s_ready(s_rsp.arready),
        .d_data(m_req.ar),.d_valid(m_req.arvalid),.d_ready(m_rsp.arready));
    or_bo_xpm_mailbox #(.WIDTH($bits(ax_r_t)),.WAIT_CONSUMED(0)) r(
        .reset_n,.s_clk(m_clk),.s_reset_n(m_reset_n),.d_clk(s_clk),.d_reset_n(s_reset_n),
        .s_data(m_rsp.r),.s_valid(m_rsp.rvalid),.s_ready(m_req.rready),
        .d_data(s_rsp.r),.d_valid(s_rsp.rvalid),.d_ready(s_req.rready));
endmodule
