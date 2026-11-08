// Bundled-data, one-entry asynchronous mailbox. Payload remains stable until
// acknowledge returns. Both domains must share reset assertion; local reset
// deassertion is synchronized by the top. Independent live resets are unsupported.
module or_bo_cdc_mailbox #(parameter int WIDTH=32, parameter bit SYNC_PAYLOAD=1'b0)(
    input wire s_clk,s_reset_n,d_clk,d_reset_n,
    input wire [WIDTH-1:0] s_data,input wire s_valid,output wire s_ready,
    output logic [WIDTH-1:0] d_data,output logic d_valid,input wire d_ready
);
    logic [WIDTH-1:0] payload;
    logic request,ack;
    (* ASYNC_REG="TRUE" *) logic req_meta,req_sync,ack_meta,ack_sync;
    wire [WIDTH-1:0] received_payload;
    wire received_request;
    generate if(SYNC_PAYLOAD) begin: synchronized_payload
        // Narrow response channel: the payload also crosses a real two-FF
        // synchronizer. It remains held until the receiver consumes the word.
        // Delay the synchronized request by one more destination clock so a
        // payload bits have an additional destination cycle to settle before
        // the held word is captured. This does not model analog metastability.
        (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [WIDTH-1:0] data_meta,data_sync;
        logic req_settled;
        always_ff @(posedge d_clk or negedge d_reset_n) begin
            if(!d_reset_n) begin data_meta<='0;data_sync<='0;req_settled<=0;end
            else begin data_meta<=payload;data_sync<=data_meta;req_settled<=req_sync;end
        end
        assign received_payload=data_sync;
        assign received_request=req_settled;
    end else begin: bundled_payload
        assign received_payload=payload;
        assign received_request=req_sync;
    end endgenerate
    assign s_ready=s_reset_n && request==ack_sync;
    always_ff @(posedge s_clk or negedge s_reset_n) begin
        if(!s_reset_n) begin request<=0;payload<=0;ack_meta<=0;ack_sync<=0;end
        else begin
            ack_meta<=ack;ack_sync<=ack_meta;
            if(s_valid && s_ready) begin payload<=s_data;request<=!request;end
        end
    end
    always_ff @(posedge d_clk or negedge d_reset_n) begin
        if(!d_reset_n) begin req_meta<=0;req_sync<=0;ack<=0;d_valid<=0;d_data<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(!d_valid && received_request!=ack) begin d_data<=received_payload;d_valid<=1;end
            if(d_valid && d_ready) begin d_valid<=0;ack<=received_request;end
        end
    end
endmodule

module or_bo_reset_sync(input wire clk,reset_n,output wire local_reset_n);
    (* ASYNC_REG="TRUE" *) logic [1:0] sync;
    always_ff @(posedge clk or negedge reset_n)
        if(!reset_n) sync<=0; else sync<={sync[0],1'b1};
    assign local_reset_n=sync[1];
endmodule
