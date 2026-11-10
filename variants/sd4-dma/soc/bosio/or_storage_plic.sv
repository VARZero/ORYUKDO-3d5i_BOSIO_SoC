// Two level-triggered sources, standard PLIC M/S contexts for hart 0.
// A claimed source cannot be re-pended until its owning context completes it.
module or_storage_plic(
 input wire clk,reset_n,input wire [1:0] sources,
 input or_bo_axi_pkg::al_req_t req,output or_bo_axi_pkg::al_rsp_t rsp,
 output wire m_irq,s_irq
);
 wire valid,store;wire [31:0] address,write_data;wire [3:0] mask;
 logic [31:0] read_data;wire error=address[1:0]!=0 || (store && mask!=15);
 gen3_axil_regs bus(.clk,.reset_n,.req,.rsp,.valid,.store,.address,.write_data,.mask,
  .ready(1'b1),.error,.read_data);
 logic [2:0] priority_value[2],threshold[2];
 logic [1:0] enabled[2],pending,in_service,service_owner;
 logic [1:0] selected[2];
 wire [21:0] offset=address[21:0];
 assign m_irq=selected[0]!=0;assign s_irq=selected[1]!=0;
 always_comb begin
   for(int c=0;c<2;c++) begin
     selected[c]=0;
     for(int i=1;i>=0;i--) if(pending[i] && enabled[c][i] && priority_value[i]>threshold[c] &&
       (selected[c]==0 || priority_value[i]>=priority_value[1'(selected[c]-1'b1)])) selected[c]=2'(i+1);
   end
   read_data=0;
   case(offset)
    'h4:read_data={29'b0,priority_value[0]};
    'h8:read_data={29'b0,priority_value[1]};
    'h1000:read_data={29'b0,pending,1'b0};
    'h2000:read_data={29'b0,enabled[0],1'b0};
    'h2080:read_data={29'b0,enabled[1],1'b0};
    'h200000:read_data={29'b0,threshold[0]};
    'h201000:read_data={29'b0,threshold[1]};
    'h200004:read_data={30'b0,selected[0]};
    'h201004:read_data={30'b0,selected[1]};
    default:;
   endcase
 end
 always_ff @(posedge clk) begin
   if(!reset_n) begin
     pending<=0;in_service<=0;service_owner<=0;
     for(int c=0;c<2;c++) begin priority_value[c]<=0;threshold[c]<=0;enabled[c]<=0;end
   end else begin
     pending<=pending | (sources & ~in_service);
     if(valid && !error) begin
       if(store) case(offset)
        'h4:priority_value[0]<=write_data[2:0];
        'h8:priority_value[1]<=write_data[2:0];
        'h2000:enabled[0]<=write_data[2:1];
        'h2080:enabled[1]<=write_data[2:1];
        'h200000:threshold[0]<=write_data[2:0];
        'h201000:threshold[1]<=write_data[2:0];
        default:;
       endcase
       for(int c=0;c<2;c++) if(offset==(c==0?22'h200004:22'h201004)) begin
         if(!store && selected[c]!=0) begin
           pending[1'(selected[c]-1'b1)]<=0;in_service[1'(selected[c]-1'b1)]<=1;service_owner[1'(selected[c]-1'b1)]<=1'(c);
         end else if(store && write_data>=1 && write_data<=2 &&
           in_service[1'(write_data[1:0]-1'b1)] && service_owner[1'(write_data[1:0]-1'b1)]==1'(c)) in_service[1'(write_data[1:0]-1'b1)]<=0;
       end
     end
   end
 end
endmodule
