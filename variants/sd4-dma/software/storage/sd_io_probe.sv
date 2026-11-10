// Timing-only fixture. Never program this test design onto the board.
module sd_io_probe(input wire sys_clk_p,sys_clk_n,rst_n,
 output wire error,sd_dclk,inout wire sd_cmd,inout wire [3:0] sd_dat);
 wire raw,feedback,feedback_buf,clock_raw,clk,locked;
 IBUFDS input_clock(.I(sys_clk_p),.IB(sys_clk_n),.O(raw));
 MMCME2_BASE #(.CLKIN1_PERIOD(5.0),.CLKFBOUT_MULT_F(5.0),.CLKOUT0_DIVIDE_F(10.0)) clocking_unit(
 .CLKIN1(raw),.RST(!rst_n),.PWRDWN(1'b0),.CLKFBIN(feedback_buf),
 .CLKFBOUT(feedback),.CLKOUT0(clock_raw),.LOCKED(locked));
 BUFG feedback_clock(.I(feedback),.O(feedback_buf));
 BUFG fabric_clock(.I(clock_raw),.O(clk));
 (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe;
 always @(posedge clk or negedge rst_n)
 if(!rst_n)reset_pipe<=0;else reset_pipe<={reset_pipe[1:0],locked};
 wire reset_n=reset_pipe[2];
 reg [31:0] counter;
 always @(posedge clk) if(!reset_n)counter<=0;else counter<=counter+1;
 wire busy,done;wire [2:0] failure;wire [127:0] response;
 wire [7:0] read_byte;wire cmd_o,cmd_t,cmd_i;
 wire [3:0] dat_o,dat_t,dat_i;
 or_sd_native phy(.clk(clk),.reset_n(reset_n),.start(!busy && counter[12:0]==0),
 .command(counter[24:19]),.argument(counter),.response_type(counter[16:15]),
 .check_crc(1'b1),.four_bit(1'b1),.data_present(1'b1),.data_write(counter[18]),
 .data_bytes(10'd512),.half_period(16'd2),.busy(busy),.done(done),.error(failure),
 .response(response),.buffer_address(counter[8:0]),.buffer_wdata(counter[16:9]),
 .buffer_we(!busy),.buffer_rdata(read_byte),.sd_clk(sd_dclk),
 .sd_cmd_o(cmd_o),.sd_cmd_t(cmd_t),.sd_cmd_i(cmd_i),
 .sd_dat_o(dat_o),.sd_dat_t(dat_t),.sd_dat_i(dat_i));
 IOBUF cmd_pad(.I(cmd_o),.T(cmd_t),.O(cmd_i),.IO(sd_cmd));
 for(genvar i=0;i<4;i++)begin
 IOBUF data_pad(.I(dat_o[i]),.T(dat_t[i]),.O(dat_i[i]),.IO(sd_dat[i]));
 end
 reg result;
 always @(posedge clk)result<=^response ^ ^failure ^ ^read_byte ^done;
 assign error=result;
endmodule
