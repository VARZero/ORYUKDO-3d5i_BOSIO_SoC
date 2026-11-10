module or_bo_cpu_axi #(parameter bit FETCH_BURST=1) (
    input wire clk,reset_n,
    input wire if_valid,output wire if_ready,input wire [31:0] if_address,
    output wire if_response_valid,input wire if_response_ready,
    output logic [95:0] if_data,output logic [2:0] if_fault,
    input wire data_valid,output wire data_ready,input wire data_store,
    input wire [31:0] data_address,data_write,input wire [3:0] data_mask,
    output wire data_response_valid,input wire data_response_ready,
    output logic [31:0] data_read,output logic data_fault,output wire [4:0] data_cause,
    output or_bo_axi_pkg::ax_req_t req,input or_bo_axi_pkg::ax_rsp_t rsp
);
    import or_bo_axi_pkg::*;
    typedef enum logic [2:0] {IDLE,READ_ADDR,READ_DATA,WRITE,WRITE_RESP,DONE} state_t;
    state_t state;
    logic fetching,store,prefer_data,aw_done,w_done;
    // Fetch and data share the AXI engine, not response consumption. Decode can
    // stall a fetch while awaiting an older load; keeping AXI in DONE until that
    // fetch is consumed would prevent the load and deadlock both interfaces.
    logic if_pending,data_pending,response_store;
    logic [31:0] address,write_data;
    logic [3:0] mask;
    logic [1:0] word_index,burst_left;
    logic [1:0] burst_words;
    // Fetch the existing three-instruction bundle in one AXI transaction when
    // possible. All supported fetch regions end on a 4 KiB boundary.
    always_comb begin
        burst_words=1;
        if(FETCH_BURST && fetching) begin
            burst_words=2'd3-word_index;
            if(address[11:2]==10'h3ff) burst_words=1;
            else if(address[11:2]==10'h3fe && burst_words>2) burst_words=2;
        end
    end
    wire choose_data=data_valid && !data_pending && (!if_valid || if_pending || prefer_data);
    wire choose_fetch=if_valid && !if_pending && !choose_data;
    wire fetch_ok=(address>=32'h10000 && address<32'h11000) ||
                  (address>=32'h20000 && address<32'h60000) ||
                  (address>=32'h80000000 && address<32'hc0000000);
    assign if_ready=reset_n && state==IDLE && !if_pending && !choose_data;
    assign data_ready=reset_n && state==IDLE && choose_data;
    assign if_response_valid=reset_n && if_pending;
    assign data_response_valid=reset_n && data_pending;
    assign data_cause=response_store?5'd7:5'd5;
    always_comb begin
        req='0;
        req.ar.addr={32'b0,address};req.ar.len=8'(burst_words-1'b1);req.ar.size=2;req.ar.burst=1;req.ar.user=fetching?4'hf:mask;
        req.aw=req.ar;req.w.data=write_data;req.w.strb=mask;req.w.last=1;
        req.arvalid=reset_n && state==READ_ADDR && (!fetching || fetch_ok);
        req.rready=reset_n && state==READ_DATA;
        req.awvalid=reset_n && state==WRITE && !aw_done;
        req.wvalid=reset_n && state==WRITE && !w_done;
        req.bready=reset_n && state==WRITE_RESP;
    end
    always_ff @(posedge clk) begin
        if(!reset_n) begin state<=IDLE;fetching<=0;store<=0;prefer_data<=1;address<=0;
            write_data<=0;mask<=0;word_index<=0;burst_left<=0;if_data<=0;if_fault<=0;
            data_read<=0;data_fault<=0;aw_done<=0;w_done<=0;
            if_pending<=0;data_pending<=0;response_store<=0;end
        else begin
          if(if_pending && if_response_ready) if_pending<=0;
          if(data_pending && data_response_ready) data_pending<=0;
          case(state)
            IDLE: if(choose_data || choose_fetch) begin
                fetching<=!choose_data;store<=choose_data && data_store;
                prefer_data<=!choose_data;word_index<=0;
                if(choose_data) data_fault<=0;
                else begin if_fault<=0;if_data<=0;end
                address<=choose_data?{data_address[31:2],2'b0}:if_address;
                write_data<=data_write;mask<=data_mask;aw_done<=0;w_done<=0;
                state<=choose_data && data_store?WRITE:READ_ADDR;
            end
            READ_ADDR: if(fetching && !fetch_ok) begin
                if_fault[word_index]<=1;
                if(word_index==2) state<=DONE;
                else begin word_index<=word_index+1'b1;address<=address+4;end
            end else if(rsp.arready) begin burst_left<=burst_words;state<=READ_DATA;end
            READ_DATA: if(rsp.rvalid) begin
                if(fetching) begin
                    if_data[32*word_index+:32]<=rsp.r.data;
                    if_fault[word_index]<=rsp.r.resp[1] || (rsp.r.last!=(burst_left==1));
                    burst_left<=burst_left-1'b1;
                    if(word_index==2) state<=DONE;
                    else begin
                        word_index<=word_index+1'b1;address<=address+4;
                        if(burst_left==1) state<=READ_ADDR;
                    end
                end else begin data_read<=rsp.r.data;data_fault<=rsp.r.resp[1] || !rsp.r.last;state<=DONE;end
            end
            WRITE: begin
                if(req.awvalid && rsp.awready) aw_done<=1;
                if(req.wvalid && rsp.wready) w_done<=1;
                if((aw_done || rsp.awready) && (w_done || rsp.wready)) state<=WRITE_RESP;
            end
            WRITE_RESP: if(rsp.bvalid) begin data_fault<=rsp.b.resp[1];data_read<=0;state<=DONE;end
            DONE: begin
                if(fetching) if_pending<=1;
                else begin data_pending<=1;response_store<=store;end
                state<=IDLE;
            end
            default: state<=IDLE;
          endcase
        end
    end
endmodule
