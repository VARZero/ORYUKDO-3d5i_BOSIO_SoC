// Single-master, byte-command I2C. Open drain: *_t=1 releases the line.
// CMD: START[0], STOP[1], READ[2], WRITE[3], read-NACK[4], clear-status[5].
// B response acknowledges a command; STATUS.done is wire-level completion.
module gen3_axi_i2c(
    input wire clk,reset_n,scl_i,sda_i,output logic scl_t,sda_t,
    input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp
);
    wire valid,store;wire [31:0] address,write_data;wire [3:0] mask;
    logic [31:0] read_data;logic error;
    gen3_axil_regs bus(.clk,.reset_n,.req,.rsp,.valid,.store,.address,.write_data,.mask,.ready(1'b1),.error,.read_data);
    typedef enum logic [3:0] {IDLE,START_PREP,START_RAISE,START_HOLD,BIT_LOW,BIT_HIGH,ACK_LOW,ACK_HIGH,STOP_LOW,STOP_HIGH,STOP_RELEASE} state_t;
    state_t state;
    (* ASYNC_REG="TRUE" *) logic scl_meta,scl_sync,sda_meta,sda_sync;
    logic [7:0] tx_data,rx_data,shift;logic [2:0] bit_index;
    logic [15:0] divider,ticks;logic [31:0] timeout_limit,wait_count;
    logic owned,done,nack,timed_out,collision,read_cmd,stop_cmd,read_nack,do_byte;
    wire busy=state!=IDLE;
    wire fire=valid && store && !error;
    wire launch=fire && address[7:0]==16 && mask[0] && |write_data[3:0];
    wire [15:0] period_clocks=divider<8?16'd8:divider;
    wire high_phase=state==START_RAISE || state==BIT_HIGH || state==ACK_HIGH || state==STOP_HIGH;
    always_comb begin
        error=address[1:0]!=0;read_data=0;
        case(address[7:0])
            0:begin read_data={24'b0,rx_data};if(store && busy) error=1;end
            4:begin read_data={24'b0,sda_sync,scl_sync,owned,collision,timed_out,nack,done,busy};if(store) error=1;end
            8:begin read_data={16'b0,divider};if(store && busy) error=1;end
            12:begin read_data=timeout_limit;if(store && busy) error=1;end
            16:if(store && mask[0] && |write_data[3:0]) begin
                if(busy || (&write_data[3:2]) || (!owned && !write_data[0]) ||
                   (!write_data[0] && !write_data[1] && !write_data[2] && !write_data[3])) error=1;
            end
            default:error=1;
        endcase
    end
    task automatic finish_command;
        begin state<=IDLE;done<=1;ticks<=0;wait_count<=0;end
    endtask
    task automatic after_start;
        begin
            scl_t<=0;ticks<=period_clocks-1'b1;
            if(do_byte) begin state<=BIT_LOW;sda_t<=read_cmd?1'b1:shift[7];end
            else if(stop_cmd) begin state<=STOP_LOW;sda_t<=0;end
            else finish_command();
        end
    endtask
    always_ff @(posedge clk) begin
        if(!reset_n) begin state<=IDLE;scl_t<=1;sda_t<=1;scl_meta<=1;scl_sync<=1;sda_meta<=1;sda_sync<=1;
            tx_data<=0;rx_data<=0;shift<=0;bit_index<=7;divider<=500;ticks<=0;timeout_limit<=1000000;wait_count<=0;
            owned<=0;done<=0;nack<=0;timed_out<=0;collision<=0;read_cmd<=0;stop_cmd<=0;read_nack<=0;do_byte<=0;end
        else begin
            scl_meta<=scl_i;scl_sync<=scl_meta;sda_meta<=sda_i;sda_sync<=sda_meta;
            if(fire) case(address[7:0])
                0:if(mask[0]) tx_data<=write_data[7:0];
                8:begin if(mask[0]) divider[7:0]<=write_data[7:0];if(mask[1]) divider[15:8]<=write_data[15:8];end
                12:for(int n=0;n<4;n++) if(mask[n]) timeout_limit[n*8+:8]<=write_data[n*8+:8];
                16:if(mask[0] && write_data[5]) begin done<=0;nack<=0;timed_out<=0;collision<=0;end
                default:;
            endcase
            if(launch) begin
                done<=0;nack<=0;timed_out<=0;collision<=0;wait_count<=0;ticks<=period_clocks-1'b1;
                read_cmd<=write_data[2];stop_cmd<=write_data[1];read_nack<=write_data[4];do_byte<=|write_data[3:2];
                shift<=tx_data;bit_index<=7;
                if(write_data[0]) begin state<=START_PREP;scl_t<=!owned;sda_t<=1;end
                else if(|write_data[3:2]) begin state<=BIT_LOW;scl_t<=0;sda_t<=write_data[2]?1'b1:tx_data[7];end
                else begin state<=STOP_LOW;scl_t<=0;sda_t<=0;end
            end else if(busy) begin
                if(high_phase && !scl_sync) begin
                    // Count the entire stretch, including the input synchronizer delay.
                    if(wait_count >= (timeout_limit==0?32'd1:timeout_limit)-1'b1) begin
                        timed_out<=1;owned<=0;scl_t<=1;sda_t<=1;finish_command();
                    end else wait_count<=wait_count+1'b1;
                end else begin
                    wait_count<=0;
                    if(ticks!=0) ticks<=ticks-1'b1;
                    else begin
                        ticks<=period_clocks-1'b1;
                        case(state)
                            START_PREP:begin scl_t<=1;state<=START_RAISE;end
                            START_RAISE:if(!sda_sync) begin collision<=1;owned<=0;scl_t<=1;sda_t<=1;finish_command();end
                                else begin sda_t<=0;owned<=1;state<=START_HOLD;end
                            START_HOLD:after_start();
                            BIT_LOW:begin scl_t<=1;state<=BIT_HIGH;end
                            BIT_HIGH:begin
                                scl_t<=0;
                                if(!read_cmd && sda_t && !sda_sync) begin collision<=1;owned<=0;scl_t<=1;sda_t<=1;finish_command();end
                                else begin
                                    if(read_cmd) shift<={shift[6:0],sda_sync};
                                    if(bit_index==0) begin state<=ACK_LOW;sda_t<=read_cmd?read_nack:1'b1;end
                                    else begin bit_index<=bit_index-1'b1;state<=BIT_LOW;if(!read_cmd) sda_t<=shift[bit_index-1'b1];end
                                end
                            end
                            ACK_LOW:begin scl_t<=1;state<=ACK_HIGH;end
                            ACK_HIGH:begin
                                scl_t<=0;sda_t<=1;
                                if(read_cmd) rx_data<=shift;else nack<=sda_sync;
                                if(stop_cmd) begin state<=STOP_LOW;sda_t<=0;end
                                else finish_command();
                            end
                            STOP_LOW:begin scl_t<=1;state<=STOP_HIGH;end
                            STOP_HIGH:begin sda_t<=1;state<=STOP_RELEASE;end
                            STOP_RELEASE:begin owned<=0;finish_command();end
                            default:begin owned<=0;scl_t<=1;sda_t<=1;finish_command();end
                        endcase
                    end
                end
            end
        end
    end
endmodule
