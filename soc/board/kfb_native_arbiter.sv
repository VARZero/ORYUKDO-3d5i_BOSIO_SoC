`timescale 1ns/1ps
// Two native clients in MIG ui_clk. Read tags reserve response ownership;
// independent command/WDF handshakes are both required to finish a write.
module kfb_native_arbiter(
 input wire clk,reset_n,
 input wire [1:0] req_valid,req_write,
 input wire [28:0] req_addr[2],input wire [255:0] req_data[2],
 input wire [31:0] req_mask[2],output logic [1:0] req_ready,
 output wire [1:0] rsp_valid,output wire [255:0] rsp_data,
 output wire app_en,output wire [2:0] app_cmd,output wire [28:0] app_addr,
 input wire app_rdy,output wire app_wdf_wren,app_wdf_end,
 output wire [255:0] app_wdf_data,output wire [31:0] app_wdf_mask,
 input wire app_wdf_rdy,input wire app_rd_data_valid,app_rd_data_end,
 input wire [255:0] app_rd_data
);
 logic active,owner,rr,writing,cmd_sent,data_sent;
 logic [28:0] address;logic [255:0] data;logic [31:0] mask;
 logic [15:0] tags;logic [3:0] wp,rp;logic [4:0] count;
 wire space=count<16;
 assign app_en=reset_n && active && !cmd_sent && (writing || space);
 assign app_cmd=writing?3'b000:3'b001;
 assign app_addr=address;
 assign app_wdf_wren=reset_n && active && writing && !data_sent;
 assign app_wdf_end=app_wdf_wren;
 assign app_wdf_data=data;assign app_wdf_mask=mask;
 wire cmd_fire=app_en && app_rdy;
 wire data_fire=app_wdf_wren && app_wdf_rdy;
 wire accepted=active && (writing?((cmd_sent || cmd_fire) && (data_sent || data_fire)):cmd_fire);
 wire read_push=cmd_fire && !writing;
 wire read_pop=app_rd_data_valid && app_rd_data_end;
 assign rsp_valid=reset_n && read_pop && count!=0 ? (2'b01<<tags[rp]):2'b00;
 assign rsp_data=app_rd_data;
 always_comb begin req_ready=0;if(reset_n && accepted)req_ready[owner]=1;end
 always_ff @(posedge clk) begin
  if(!reset_n)begin active<=0;owner<=0;rr<=0;writing<=0;cmd_sent<=0;data_sent<=0;
   address<=0;data<=0;mask<='1;tags<=0;wp<=0;rp<=0;count<=0;end
  else begin
   if(!active && (|req_valid))begin
    owner<=req_valid[rr]?rr:!rr;
    writing<=req_write[req_valid[rr]?rr:!rr];
    address<=req_addr[req_valid[rr]?rr:!rr];
    data<=req_data[req_valid[rr]?rr:!rr];mask<=req_mask[req_valid[rr]?rr:!rr];
    active<=1;cmd_sent<=0;data_sent<=0;
   end
   if(cmd_fire)cmd_sent<=1;
   if(data_fire)data_sent<=1;
   if(accepted)begin active<=0;rr<=!owner;end
   if(read_push)begin tags[wp]<=owner;wp<=wp+1'b1;end
   if(read_pop)rp<=rp+1'b1;
   case({read_push,read_pop})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
    default:begin end
   endcase
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(reset_n)begin
  assert(count<=16)else $fatal(1,"MIG read tag overflow");
  if(read_pop)assert(count!=0)else $fatal(1,"Unowned MIG response");
  if(app_rd_data_valid)assert(app_rd_data_end)else $fatal(1,"Expected one 256-bit MIG UI beat");
  if(active)assert(req_valid[owner])else $fatal(1,"Native request revoked before acceptance");
 end
 // synthesis translate_on
endmodule
