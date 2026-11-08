// Byte-oriented polling SPI master. CPOL/CPHA 0..3, MSB first, one CS.
// CTRL[2] keeps CS asserted between bytes. Divider is clocks per half period.
module gen3_axi_spi(
    input wire clk,reset_n,miso,output logic sck,mosi,output wire cs_n,
    input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp
);
    wire valid,store;wire [31:0] address,write_data;wire [3:0] mask;
    logic error;logic [31:0] read_data;
    gen3_axil_regs bus(.clk,.reset_n,.req,.rsp,.valid,.store,.address,.write_data,.mask,.ready(1'b1),.error,.read_data);
    logic [7:0] tx_data,rx_data,tx_shift,rx_shift;
    logic [15:0] divider,ticks;logic [4:0] edge_count;logic [2:0] cfg;
    logic busy,done;
    (* ASYNC_REG="TRUE" *) logic miso_meta,miso_sync;
    assign cs_n=!(busy || cfg[2]);
    wire fire=valid && store && !error;
    wire start=fire && address[7:0]==8'h10 && mask[0] && write_data[0];
    always_comb begin
        read_data=0;error=address[1:0]!=0;
        case(address[7:0])
            0:begin read_data={24'b0,rx_data};if(store && busy) error=1;end
            4:begin read_data={29'b0,!cs_n,done,busy};if(store) error=1;end
            8:begin read_data={16'b0,divider};if(store && busy) error=1;end
            12:begin read_data={29'b0,cfg};if(store && busy) error=1;end
            16:if(store && mask[0] && write_data[0] && busy) error=1;
            default:error=1;
        endcase
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin tx_data<=0;rx_data<=0;tx_shift<=0;rx_shift<=0;divider<=50;ticks<=0;edge_count<=0;cfg<=0;busy<=0;done<=0;sck<=0;mosi<=0;miso_meta<=0;miso_sync<=0;end
        else begin
            miso_meta<=miso;miso_sync<=miso_meta;
            if(fire) case(address[7:0])
                0:if(mask[0]) tx_data<=write_data[7:0];
                8:begin
                    if(mask[0]) divider[7:0]<=write_data[7:0];
                    if(mask[1]) divider[15:8]<=write_data[15:8];
                end
                12:if(mask[0]) begin cfg<=write_data[2:0];sck<=write_data[0];end
                16:if(mask[0] && write_data[1]) done<=0;
                default:;
            endcase
            if(start) begin
                busy<=1;done<=0;edge_count<=0;ticks<=(divider<8?16'd8:divider)-1'b1;
                tx_shift<=tx_data;rx_shift<=0;sck<=cfg[0];mosi<=cfg[1]?1'b0:tx_data[7];
            end else if(busy) begin
                if(ticks!=0) ticks<=ticks-1'b1;
                else begin
                    ticks<=(divider<8?16'd8:divider)-1'b1;sck<=!sck;edge_count<=edge_count+1'b1;
                    if(edge_count[0]==cfg[1]) rx_shift<={rx_shift[6:0],miso_sync};
                    else begin tx_shift<={tx_shift[6:0],1'b0};mosi<=cfg[1]?tx_shift[7]:tx_shift[6];end
                    if(edge_count==15) begin busy<=0;done<=1;sck<=cfg[0];rx_data<=cfg[1]?{rx_shift[6:0],miso_sync}:rx_shift;end
                end
            end
        end
    end
endmodule
