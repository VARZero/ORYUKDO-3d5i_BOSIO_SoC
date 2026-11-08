`timescale 1ns/1ps
module tb_gen3_bosio
`ifdef VERILATOR
(input wire cpu_clk,fabric_clk,reset_n)
`endif
;

    import or_bo_axi_pkg::*;
    `ifndef VERILATOR
    reg cpu_clk=0,fabric_clk=0,reset_n=0;
    always #10 cpu_clk=~cpu_clk;
    always #5 fabric_clk=~fabric_clk;
    initial begin #200;reset_n=1;end
    `endif
    ax_req_t memory;ax_rsp_t memory_reply;
    wire uart_tx,retire,trap;wire [31:0] retire_pc,trap_pc;wire [4:0] trap_cause;
    wire [23:0] video_data;wire video_valid,video_sof,video_eol;
    int cycles=0,retired=0,snoops=0,grants=0,pixels=0;
    wire video_ready=(cycles%7)!=0;
    wire gp_uart_tx,gp_spi_mosi,gp_spi_sck,gp_spi_cs_n,gp_scl_t,gp_sda_t;
    reg held=0;reg [25:0] held_pixel;
    gen3_bosio_soc dut(.cpu_clk,.fabric_clk,.reset_n,.uart_rx(1'b1),.uart_tx,.memory,.memory_reply,
        .gp_uart_rx(gp_uart_tx),.gp_uart_tx,.gp_spi_miso(gp_spi_mosi),.gp_spi_mosi,.gp_spi_sck,.gp_spi_cs_n,
        .gp_i2c_scl_i(gp_scl_t),.gp_i2c_sda_i(gp_sda_t),.gp_i2c_scl_t(gp_scl_t),.gp_i2c_sda_t(gp_sda_t),.gp_i2c_scl_o(),.gp_i2c_sda_o(),
        .retire,.trap,.retire_pc,.trap_pc,.trap_cause,.video_ready(video_ready),.video_data,.video_valid,.video_sof,.video_eol,
        .reference_iic_scl_i(1'b1),.reference_iic_sda_i(1'b1),
        .reference_iic_scl_o(),.reference_iic_scl_t(),.reference_iic_sda_o(),.reference_iic_sda_t());
    `ifdef KFB_NATIVE_BACKEND
    `define TEST_MEMORY ram.backend.mem
    kfb_axi_ram_model ram(.clk(fabric_clk),.reset_n,.req(memory),.rsp(memory_reply));
    `else
    `define TEST_MEMORY ram.mem
    axi_ram_model ram(.clk(fabric_clk),.reset_n,.req(memory),.rsp(memory_reply));
    `endif
    string image_name,uart_text="";
    int reads[4]='{default:0},writes[4]='{default:0};
    reg [31:0] last_pc=0;reg [7:0] uart_byte;
    initial begin
        if(!$value$plusargs("image=%s",image_name)) $fatal(1,"Missing image plusarg");

    end
    always @(posedge cpu_clk) if(reset_n) begin
        if($test$plusargs("operand_check")) begin
            for(int lane=0;lane<5;lane++) if(dut.soc.cpu.issue[lane] && dut.soc.cpu.take[lane]) begin
                for(int src=0;src<2;src++) begin
                    automatic logic [5:0] phy;
                    automatic logic [31:0] expected_operand,actual_operand;
                    phy=src ? dut.soc.cpu.ex[lane].rs2 : dut.soc.cpu.ex[lane].rs1;
                    actual_operand=src ? dut.soc.cpu.b[lane] : dut.soc.cpu.a[lane];
                    expected_operand=dut.soc.cpu.prf[phy];
                    for(int port=0;port<5;port++)
                        if(dut.soc.cpu.accepted[port] && dut.soc.cpu.wb_rd[port]==phy)
                            expected_operand=dut.soc.cpu.wb_value[port];
                    if(phy==0) expected_operand=0;
                    if(actual_operand!==expected_operand)
                        $fatal(1,"Operand stale lane=%0d src=%0d phy=%0d pc=%h got=%h expected=%h",lane,src,phy,dut.soc.cpu.ex[lane].tag[31:0],actual_operand,expected_operand);
                end
            end
        end
        if(retire) begin retired<=retired+1;last_pc<=retire_pc;end
        if(trap) $fatal(1,"CPU trap pc=%h cause=%d",trap_pc,trap_cause);
        if(dut.invalidate) snoops<=snoops+1;
    end
    always @(posedge cpu_clk) if(reset_n && $test$plusargs("trace")) begin
        if(dut.soc.cpu.redirect || dut.soc.cpu.scheduler.oldest_window_begin || dut.soc.cpu.scheduler.cp_push || dut.soc.cpu.branch_valid)
            $display("TRACE t=%0t head=%d begin=%b base=%h cp=%b tag=%h br=%b brdata=%h redir=%b target=%h kill=%b boundary=%h masks=%p",$time,
                dut.soc.cpu.oldest,dut.soc.cpu.scheduler.oldest_window_begin,dut.soc.cpu.base_pc,dut.soc.cpu.scheduler.cp_push,
                dut.soc.cpu.scheduler.nel_fcl_jumpbranch_pc,dut.soc.cpu.branch_valid,dut.soc.cpu.branch_data,
                dut.soc.cpu.redirect,dut.soc.cpu.redirect_pc,dut.soc.cpu.kill_active,dut.soc.cpu.boundary,
                dut.soc.cpu.scheduler.U_FLOW_CONTROL_LOGIC.fdu_killed);
    end
    int uart_count=0,uart_bit=0;reg uart_receiving=0;
    // Independent expected scene sample: (1,1,1) barycentrics at resolution 16
    // maps to directory 177, cell 110. Pattern scene directory 177 adds 256.
    wire pattern_scene=$test$plusargs("pattern_scene");
    wire [23:0] expected_pixel=pattern_scene ? 24'h2e48b7 : 24'habcdef;
    integer trace_fd=0;
    initial if($test$plusargs("io_trace")) trace_fd=$fopen("render_trace.txt","w");
    always @(negedge fabric_clk) if(reset_n && $test$plusargs("render_check")) begin
        if(dut.bosio.output0.selected_cfg_we && dut.bosio.output0.selected_cfg_data !==
            (dut.bosio.output0.selected_cfg_idx%3==0 ? 32'd1 : 32'd0)) $fatal(1,"Wrong CPU camera coefficient");
        if(dut.bosio.output0.transformed_we && dut.bosio.output0.transformed_data !==
            (dut.bosio.output0.transformed_idx%3==0 ? 32'd1 : 32'd0)) $fatal(1,"Wrong transformed camera coefficient");
        if(dut.bosio.output0.v0 && {dut.bosio.output0.f0,dut.bosio.output0.n0,dut.bosio.output0.n2,dut.bosio.output0.den}
            !== {5'd0,32'd1,32'd1,32'd3}) $fatal(1,"Wrong projector coordinate");
        if(dut.bosio.output0.v1 && {dut.bosio.output0.f1,dut.bosio.output0.l0,dut.bosio.output0.l2}
            !== {5'd0,16'h2aaa,16'h2aaa}) $fatal(1,"Wrong normalized coordinate");
        if(dut.bosio.output0.v2 && {dut.bosio.output0.directory_addr,dut.bosio.output0.cell_addr}
            !== {13'd177,10'd110}) $fatal(1,"Wrong tile address");
        if(dut.bosio.output0.ddr_cache.u_cache.s3_valid && dut.bosio.output0.ddr_cache.u_cache.cache_req_ready &&
            (dut.bosio.output0.ddr_cache.u_cache.s3_addr !== (pattern_scene ? 32'h8003475c : 32'h8003465c) ||
             dut.bosio.output0.ddr_cache.u_cache.s3_user !== 3'd6)) $fatal(1,"Wrong texture address or byte lane");
    end
    // Sample after the NBA region on the opposite clock edge in both simulators.
    always @(negedge fabric_clk) if(reset_n && trace_fd!=0) begin
        if(dut.bosio.output0.selected_cfg_we)
            $fdisplay(trace_fd,"RAW %0d %0d %h",cycles,dut.bosio.output0.selected_cfg_idx,dut.bosio.output0.selected_cfg_data);
        if(dut.bosio.output0.u_display_transform.v0)
            $fdisplay(trace_fd,"T %0d %0d %h %h %h %h %h",cycles,dut.bosio.output0.u_display_transform.idx0,dut.bosio.output0.u_display_transform.start0,dut.bosio.output0.u_display_transform.dx0,dut.bosio.output0.u_display_transform.dy0,dut.bosio.output0.u_display_transform.diff_x,dut.bosio.output0.u_display_transform.diff_y);
        if(dut.bosio.output0.transformed_we)
            $fdisplay(trace_fd,"CFG %0d %0d %h",cycles,dut.bosio.output0.transformed_idx,dut.bosio.output0.transformed_data);
        if(dut.bosio.output0.v0)
            $fdisplay(trace_fd,"P %0d %0d %h %h %h",cycles,dut.bosio.output0.f0,dut.bosio.output0.n0,dut.bosio.output0.n2,dut.bosio.output0.den);
        if(dut.bosio.output0.v1)
            $fdisplay(trace_fd,"N %0d %0d %h %h",cycles,dut.bosio.output0.f1,dut.bosio.output0.l0,dut.bosio.output0.l2);
        if(dut.bosio.output0.v2)
            $fdisplay(trace_fd,"A %0d %0d %0d",cycles,dut.bosio.output0.directory_addr,dut.bosio.output0.cell_addr);
        if(dut.bosio.output0.ddr_cache.u_cache.s3_valid && dut.bosio.output0.ddr_cache.u_cache.cache_req_ready)
            $fdisplay(trace_fd,"C %0d %h %h",cycles,dut.bosio.output0.ddr_cache.u_cache.s3_addr,dut.bosio.output0.ddr_cache.u_cache.s3_user);
    end
    always @(posedge cpu_clk) begin
        if(!reset_n) begin uart_count<=0;uart_bit<=0;uart_receiving<=0;end
        else if(!uart_receiving) begin
            if(!uart_tx) begin uart_receiving<=1;uart_count<=647;uart_bit<=0;end
        end else if(uart_count!=0) uart_count<=uart_count-1;
        else if(uart_bit<8) begin uart_byte[uart_bit]<=uart_tx;uart_bit<=uart_bit+1;uart_count<=431;end
        else begin
            if(!uart_tx) $fatal(1,"UART stop bit");
            uart_text={uart_text,string'(uart_byte)};$write("%c",uart_byte);uart_receiving<=0;
        end
    end
    always @(posedge fabric_clk) if(reset_n) begin
        cycles<=cycles+1;
        if($test$plusargs("io_trace") && memory.arvalid && memory_reply.arready && dut.fabric.active_master==3)
            $display("MEMTRACE cycle=%0d address=%h beats=%0d",cycles,memory.ar.addr,int'(memory.ar.len)+1);
        if(memory_reply.rvalid && memory.rready) reads[dut.fabric.active_master]<=reads[dut.fabric.active_master]+1;
        if(memory.wvalid && memory_reply.wready) writes[dut.fabric.active_master]<=writes[dut.fabric.active_master]+1;
        if(dut.grant_fabric) grants<=grants+1;
        if(held && (!video_valid || {video_sof,video_eol,video_data}!==held_pixel)) $fatal(1,"Video changed under backpressure");
        held<=video_valid&&!video_ready;held_pixel<={video_sof,video_eol,video_data};
        if(video_valid && video_ready) begin
            if(video_data!==expected_pixel) $fatal(1,"Wrong output pixel %0d: %h expected=%h",pixels,video_data,expected_pixel);
            if(video_sof!==(pixels%921600==0) || video_eol!==(pixels%1280==1279)) $fatal(1,"Video SOF/EOL order");
            pixels<=pixels+1;
        end
        if(cycles%200000==199999) $display("PROGRESS cycles=%0d retired=%0d pc=%h done=%h fabric=%0d owner=%0d",cycles,retired,last_pc,`TEST_MEMORY['h7ff00/4],dut.fabric.state,dut.fabric.owner);
        if(`TEST_MEMORY['h7ff00/4][31:20]==12'hbad) $fatal(1,"Firmware failure code=%0d pc=%h",`TEST_MEMORY['h7ff00/4][19:0],last_pc);
        if(`TEST_MEMORY['h7ff00/4]==32'h600d0001 && uart_text=="G\nGEN3 BOSIO SOC OK\n" && pixels>=1280) begin
            for(int n=0;n<4;n++) if(reads[n]==0) $fatal(1,"Master %0d had no DDR reads",n);
            if(writes[1]!=512 || writes[2]!=256 || reads[3]<4480 || grants==0 || snoops!=768) $fatal(1,"Integration coverage incomplete reads=%p writes=%p snoops=%d",reads,writes,snoops);
            for(int n=0;n<256;n++) begin
                if(`TEST_MEMORY['h20000/4+n]!=(n==0?32'd12:32'h63636363)) $fatal(1,"Tile0 word %0d",n);
                if(`TEST_MEMORY['h21000/4+n]!=32'h1c1c1c1c) $fatal(1,"Tile1 word %0d",n);
            end
            if(`TEST_MEMORY['h1fffc/4]!=0 || `TEST_MEMORY['h20400/4]!=0 || `TEST_MEMORY['h20ffc/4]!=0 || `TEST_MEMORY['h21400/4]!=0) $fatal(1,"DMA overwrote guards");
            $display("PASS GEN3_BOSIO cycles=%0d retired=%0d reads=%p writes=%p snoops=%0d lock_cycles=%0d pixels=%0d output_read_beats=%0d",cycles,retired,reads,writes,snoops,grants,pixels,reads[3]);
            $finish;
        end
        if(cycles>5000000) $fatal(1,"Timeout pc=%h uart=%s",last_pc,uart_text);
    end
endmodule

`undef TEST_MEMORY
