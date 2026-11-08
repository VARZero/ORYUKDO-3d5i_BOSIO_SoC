// Internal SoC boundary. DDR controller/SD loader and display PHY are external.
module gen3_bosio_soc(
    input wire cpu_clk,fabric_clk,reset_n,uart_rx, output wire uart_tx,
    input wire gp_uart_rx,output wire gp_uart_tx,
    input wire gp_spi_miso,output wire gp_spi_sck,gp_spi_mosi,gp_spi_cs_n,
    input wire gp_i2c_scl_i,gp_i2c_sda_i,
    output wire gp_i2c_scl_o,gp_i2c_scl_t,gp_i2c_sda_o,gp_i2c_sda_t,
    output or_bo_axi_pkg::ax_req_t memory, input or_bo_axi_pkg::ax_rsp_t memory_reply,
    input wire video_ready, output wire [23:0] video_data,
    output wire video_valid,video_sof,video_eol,
    input wire reference_iic_scl_i,reference_iic_sda_i,
    output wire reference_iic_scl_o,reference_iic_scl_t,reference_iic_sda_o,reference_iic_sda_t,
    output wire trap,retire,output wire [31:0] trap_pc,retire_pc,output wire [4:0] trap_cause
);
    import or_bo_axi_pkg::*;
    wire cpu_reset_n,fabric_reset_n;
    or_bo_reset_sync fr(.clk(fabric_clk),.reset_n,.local_reset_n(fabric_reset_n));
    wire if_valid,if_ready,if_rsp_valid,if_rsp_ready,data_valid,data_ready,data_store,data_rsp_valid,data_rsp_ready,data_fault;
    wire [31:0] if_address,data_address,data_write,data_read;
    wire [95:0] if_data;wire [2:0] if_fault;wire [3:0] data_mask;
    wire lock_cpu,grant_fabric,invalidate,snoop_valid,snoop_ready;
    wire [31:0] invalidate_address,snoop_address;
    (* ASYNC_REG="TRUE" *) logic lock_meta,lock_sync,grant_meta,grant_sync;
    logic lock_source;
    logic [1:0] lock_state;
    // Register the CDC source; decoding a multi-bit FSM can glitch at 1 -> 2.
    // Four-phase handshake: never reuse a stale returned grant for the next AMO.
    always_ff @(posedge cpu_clk or negedge cpu_reset_n)
        if(!cpu_reset_n) begin lock_state<=0;lock_source<=0;grant_meta<=0;grant_sync<=0;end
        else begin
            grant_meta<=grant_fabric;grant_sync<=grant_meta;
            case(lock_state)
                0:if(lock_cpu && !grant_sync) begin lock_state<=1;lock_source<=1;end
                1:if(grant_sync) lock_state<=2;
                2:if(!lock_cpu) begin lock_state<=3;lock_source<=0;end
                3:if(!grant_sync) lock_state<=0;
            endcase
        end
    always_ff @(posedge fabric_clk or negedge fabric_reset_n)
        if(!fabric_reset_n) begin lock_meta<=0;lock_sync<=0;end
        else begin lock_meta<=lock_source;lock_sync<=lock_meta;end
    or_bo_xpm_mailbox #(32) snoop_cdc(.reset_n,.s_clk(fabric_clk),.s_reset_n(fabric_reset_n),.d_clk(cpu_clk),.d_reset_n(cpu_reset_n),
        .s_data(snoop_address),.s_valid(snoop_valid),.s_ready(snoop_ready),.d_data(invalidate_address),.d_valid(invalidate),.d_ready(1'b1));
    gen3_soc soc(.clk(cpu_clk),.reset_n,.uart_rx_pin(uart_rx),.uart_tx_pin(uart_tx),.ram_sync_reset_n(cpu_reset_n),
        .atomic_lock(lock_cpu),.atomic_grant(lock_state==2),.reservation_invalidate(invalidate),.reservation_address(invalidate_address),
        .ram_if_valid(if_valid),.ram_if_ready(if_ready),.ram_if_address(if_address),
        .ram_if_response_valid(if_rsp_valid),.ram_if_response_ready(if_rsp_ready),.ram_if_data(if_data),.ram_if_fault(if_fault),
        .ram_valid(data_valid),.ram_ready(data_ready),.ram_store(data_store),.ram_address(data_address),.ram_write_data(data_write),.ram_mask(data_mask),
        .ram_response_valid(data_rsp_valid),.ram_response_ready(data_rsp_ready),.ram_read_data(data_read),.ram_fault(data_fault),
        .trap,.trap_interrupt(),.trap_pc,.trap_value(),.trap_cause,.retire,.retire_pc);
    ax_req_t cpu_axi,masters[4],dma[3];ax_rsp_t cpu_rsp,replies[4],dma_reply[3];
    al_req_t lite[LITE_PORTS],control[3];al_rsp_t lite_rsp[LITE_PORTS],control_reply[3];
    or_bo_cpu_axi bridge(.clk(cpu_clk),.reset_n(cpu_reset_n),.if_valid,.if_ready,.if_address,
        .if_response_valid(if_rsp_valid),.if_response_ready(if_rsp_ready),.if_data,.if_fault,
        .data_valid,.data_ready,.data_store,.data_address,.data_write,.data_mask,
        .data_response_valid(data_rsp_valid),.data_response_ready(data_rsp_ready),.data_read,.data_fault,.data_cause(),.req(cpu_axi),.rsp(cpu_rsp));
    or_bo_axi_cdc cpu_crossing(.reset_n,.s_clk(cpu_clk),.s_reset_n(cpu_reset_n),.m_clk(fabric_clk),.m_reset_n(fabric_reset_n),
        .s_req(cpu_axi),.s_rsp(cpu_rsp),.m_req(masters[0]),.m_rsp(replies[0]));
    for(genvar n=0;n<3;n++) begin
        assign masters[n+1]=dma[n];assign dma_reply[n]=replies[n+1];
        assign control[n]=lite[n+1];assign lite_rsp[n+1]=control_reply[n];
    end
    or_bo_axi_fabric fabric(.clk(fabric_clk),.reset_n(fabric_reset_n),.masters,.replies,.memory,.memory_reply,.lite,.lite_reply(lite_rsp),
        .lock_request(lock_sync),.lock_grant(grant_fabric),.snoop_valid,.snoop_address,.snoop_ready,.active_master(),.busy());
    wire sensor_enable,sensor_ready,sensor_error;wire [1:0] projection_irq;
    gen3_axi_uart uart1(.clk(fabric_clk),.reset_n(fabric_reset_n),.req(lite[4]),.rsp(lite_rsp[4]),.rx(gp_uart_rx),.tx(gp_uart_tx));
    gen3_axi_spi spi1(.clk(fabric_clk),.reset_n(fabric_reset_n),.req(lite[5]),.rsp(lite_rsp[5]),
        .miso(gp_spi_miso),.mosi(gp_spi_mosi),.sck(gp_spi_sck),.cs_n(gp_spi_cs_n));
    assign gp_i2c_scl_o=1'b0;assign gp_i2c_sda_o=1'b0;
    gen3_axi_i2c i2c1(.clk(fabric_clk),.reset_n(fabric_reset_n),.req(lite[6]),.rsp(lite_rsp[6]),
        .scl_i(gp_i2c_scl_i),.sda_i(gp_i2c_sda_i),.scl_t(gp_i2c_scl_t),.sda_t(gp_i2c_sda_t));
    gen3_bosio_status status(.clk(fabric_clk),.reset_n(fabric_reset_n),.req(lite[0]),.rsp(lite_rsp[0]),
        .sensor_enable,.sensor_ready,.sensor_error,.projection_irq);
    or_bo_bosio_axi bosio(.clk(fabric_clk),.reset_n(fabric_reset_n),.control,.control_reply,.dma,.dma_reply,
        .sensor_enable,.sensor_ready,.sensor_error,.projection_irq,
        .video_ready,.video_data,.video_valid,.video_sof,.video_eol,
        .reference_iic_scl_i,.reference_iic_scl_o,.reference_iic_scl_t,.reference_iic_sda_i,.reference_iic_sda_o,.reference_iic_sda_t);
endmodule
