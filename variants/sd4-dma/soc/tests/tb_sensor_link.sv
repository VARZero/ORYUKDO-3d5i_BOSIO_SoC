`timescale 1ns/1ps
// Interface test with a static ACK/zero-read response mock, not an MPU6050 model.
// Reduced clock parameter shortens power-up/calibration; synthesis retains defaults.
module tb_sensor_link;
    reg clk=0,reset_n=0,enable=0,nack=0,accept=0;
    always #5 clk=~clk;
    wire [95:0] data;wire valid,ready,error,rx_ready,active;
    wire [31:0] yaw,pitch,roll,packets;
    wire sampled_scl,sampled_sda;
    `ifdef KFB_INPUT_CDC
    xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) scl_input(
        .src_clk(1'b0),.src_in(1'b1),.dest_clk(clk),.dest_out(sampled_scl));
    xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) sda_input(
        .src_clk(1'b0),.src_in(nack),.dest_clk(clk),.dest_out(sampled_sda));
    `else
    assign sampled_scl=1'b1;assign sampled_sda=nack;
    `endif
    bosio_sensor_hub_mpu6050 #(.CLK_HZ(1000000),.I2C_HZ(100000),.CALIBRATION_SAMPLES(4)) hub(
        .clk,.rst_n(reset_n),.enable,.iic_scl_i(sampled_scl),.iic_sda_i(sampled_sda),
        .iic_scl_o(),.iic_scl_t(),.iic_sda_o(),.iic_sda_t(),
        .m_axis_sensor_tdata(data),.m_axis_sensor_tvalid(valid),.m_axis_sensor_tready(accept&&rx_ready),
        .sensor_ready(ready),.sensor_error(error));
    bosio_out_sensor_rx rx(.clk,.rst_n(reset_n),.s_axis_sensor_tdata(data),.s_axis_sensor_tvalid(valid&&accept),
        .s_axis_sensor_tready(rx_ready),.out_yaw_mrad(yaw),.out_pitch_mrad(pitch),.out_roll_mrad(roll),
        .sensor_stream_active(active),.sensor_pkt_count(packets));
    initial begin
        repeat(5) @(negedge clk);reset_n=1;enable=1;
        wait(valid);if(!ready||error||data!==96'b0) $fatal(1,"Calibration/zero pose");
        repeat(50) begin @(negedge clk);if(!valid||data!==96'b0) $fatal(1,"Unstable stalled sensor packet");end
        accept=1;wait(packets>=2);
        if(!active||{yaw,pitch,roll}!==96'b0) $fatal(1,"Sensor/output link");
        @(negedge clk);enable=0;repeat(5) @(negedge clk);
        if(ready||valid||error) $fatal(1,"Disable state");
        nack=1;enable=1;wait(error);
        if(ready||valid) $fatal(1,"NACK produced valid pose");
        $display("PASS SENSOR_LINK calibration=4 packets=%0d stalled=50 nack=checked (static response mock)",packets);$finish;
    end
    initial begin #5000000;$fatal(1,"sensor timeout");end
endmodule
