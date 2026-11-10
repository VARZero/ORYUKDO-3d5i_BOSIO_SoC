`timescale 1ns/1ps
// Boot integration with external RAM ports, not an inferred 128 MiB FPGA array.
// Both ports use physical addresses and must return all accepted transactions.
// External port also carries committed BOSIO control accesses; DMA atomics use lock/snoop.
module gen3_soc #(
    parameter logic [31:0] RAM_BASE=32'h80000000, RAM_LIMIT=32'hc0000000,
    parameter bit EXTERNAL_RAM_PORT=1,
    parameter logic [31:0] FDT_ADDRESS=32'h87f00000
) (
    output wire atomic_lock, input wire atomic_grant,
    input wire reservation_invalidate, input wire [31:0] reservation_address,
    input wire external_m_irq,external_s_irq,
    input logic clk,reset_n,
    input logic uart_rx_pin,
    output wire uart_tx_pin, ram_sync_reset_n,
    output wire ram_if_valid,
    input logic ram_if_ready,
    output wire [31:0] ram_if_address,
    input logic ram_if_response_valid,
    output wire ram_if_response_ready,
    input logic [95:0] ram_if_data,
    input logic [2:0] ram_if_fault,
    output wire ram_valid,ram_store,
    input logic ram_ready,
    output wire [31:0] ram_address,ram_write_data,
    output wire [3:0] ram_mask,
    input logic ram_response_valid,
    output wire ram_response_ready,
    input logic [31:0] ram_read_data,
    input logic ram_fault,
    output wire trap,trap_interrupt,retire,
    output wire [31:0] trap_pc,trap_value,retire_pc,
    output wire [4:0] trap_cause
);
    // The external reset revokes transfers immediately. Only synchronous
    // state reaches the RAM bus or the scheduling datapath inside the SoC.
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [3:0] pin_release='0;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic [1:0] local_release='0;
    always_ff @(posedge clk or negedge reset_n)
        if(!reset_n) pin_release<='0;
        else pin_release<={pin_release[2:0],1'b1};
    always_ff @(posedge clk) local_release<={local_release[0],pin_release[1]};
    wire unit_reset_n=local_release[1];
    assign ram_sync_reset_n=unit_reset_n;
    wire bus_live=EXTERNAL_RAM_PORT ? pin_release[3] : unit_reset_n;
    wire if_valid,if_ready,if_response_valid,if_response_ready;
    wire [31:0] if_pc;
    wire [95:0] if_data;
    wire [2:0] if_fault;
    wire mem_valid,mem_store,mem_ready,mem_response_valid,mem_response_ready,mem_fault;
    wire [31:0] mem_address,mem_write_data,mem_read_data;
    wire [3:0] mem_mask;
    wire [63:0] timer_time;
    wire timer_irq,timer_selected;
    wire [31:0] timer_read_data;
    wire if_ram=if_pc>=RAM_BASE && if_pc<RAM_LIMIT;
    wire mem_ram=(mem_address>=32'h0c000000 && mem_address<32'h0c400000) ||
        (mem_address>=32'h10008000 && mem_address<32'h1000a000) ||
        (mem_address>=RAM_BASE && mem_address<RAM_LIMIT) ||
        (mem_address>=32'h20000000 && mem_address<32'h20030000) ||
        (mem_address>=32'h10004000 && mem_address<32'h10004020) ||
        (mem_address>=32'h10005000 && mem_address<32'h10005008) ||
        (mem_address>=32'h10006000 && mem_address<32'h10006014) ||
        (mem_address>=32'h10007000 && mem_address<32'h10007014);
    wire uart_selected=mem_address>=32'h10000000 && mem_address<32'h10000008;
    wire uart_ready;
    wire [31:0] uart_data;
    logic if_owner_ram,data_owner_ram,data_store,rom_response_valid,io_response_valid,io_fault;
    logic [95:0] rom_data;
    logic [2:0] rom_fault;
    logic [31:0] io_data;
    function automatic logic [31:0] rom_word(input logic [31:0] address);
        case(address)
            0: return 32'h100002b7; // lui t0,0x10000 (UART)
            4: return 32'h04700313; // li t1,'G'
            8: return 32'h00628023; // sb t1,0(t0)
            12: return 32'h00a00313; // li t1,'\n'
            16: return 32'h00628023;
            20: return 32'h00000513;
            24: return {FDT_ADDRESS[31:12],5'd11,7'h37};
            28: return 32'h00000613;
            32: return {RAM_BASE[31:12],5'd5,7'h37};
            36: return 32'h00028067; // jr t0
            default: return 32'h00100073;
        endcase
    endfunction
    assign ram_if_valid=bus_live && if_valid && if_ram;
    assign ram_if_address=if_pc;
    assign if_ready=unit_reset_n && (if_ram?ram_if_ready:!rom_response_valid);
    assign if_response_valid=if_owner_ram?ram_if_response_valid:rom_response_valid;
    assign if_data=if_owner_ram?ram_if_data:rom_data;
    assign if_fault=if_owner_ram?ram_if_fault:rom_fault;
    assign ram_if_response_ready=bus_live && if_owner_ram && if_response_ready;
    assign ram_valid=bus_live && mem_valid && mem_ram;
    assign ram_store=mem_store;
    assign ram_address=mem_address;
    assign ram_write_data=mem_write_data;
    assign ram_mask=mem_mask;
    assign mem_ready=mem_ram?ram_ready:(!io_response_valid && (!uart_selected || uart_ready));
    assign mem_response_valid=data_owner_ram?ram_response_valid:io_response_valid;
    assign mem_read_data=data_owner_ram?ram_read_data:io_data;
    assign mem_fault=data_owner_ram?ram_fault:io_fault;
    assign ram_response_ready=bus_live && data_owner_ram && mem_response_ready;
    gen3_cpu #(.RAM_BASE(RAM_BASE),.RAM_LIMIT(RAM_LIMIT)) cpu (
        .atomic_lock,.atomic_grant,.reservation_invalidate,.reservation_address,
        .clk,.reset_n(unit_reset_n),.scheduler_reset_n(reset_n),.timer_irq,.external_m_irq,.external_s_irq,.timer_time,.if_valid,.if_ready,.if_pc,.if_response_valid,.if_response_ready,.if_data,.if_fault,
        .mem_valid,.mem_store,.mem_ready,.mem_address,.mem_write_data,.mem_mask,.mem_response_valid,.mem_response_ready,
        .mem_read_data,.mem_fault,.trap,.trap_interrupt,.trap_pc,.trap_cause,.trap_value,.retire,.retire_pc);
    uart8250_poll uart (.clk(clk),.reset_n(unit_reset_n),.valid(mem_valid && mem_ready && uart_selected),.store(mem_store),
        .address(mem_address[2:0]),.write_data(mem_write_data),.mask(mem_mask),.ready(uart_ready),.read_data(uart_data),.rx(uart_rx_pin),.tx(uart_tx_pin));
    rv32_mtimer timer (.clk(clk),.reset_n(unit_reset_n),.write(mem_valid && mem_ready && mem_store),.address(mem_address),
        .write_data(mem_write_data),.write_mask(mem_mask),.selected(timer_selected),.read_data(timer_read_data),.timer_irq(timer_irq),.mtime(timer_time));
    always_ff @(posedge clk) begin
        if(!unit_reset_n) begin
            if_owner_ram<=0; data_owner_ram<=0; data_store<=0; rom_response_valid<=0; io_response_valid<=0;
            rom_data<=0; rom_fault<=0; io_data<=0; io_fault<=0;
        end else begin
            if(rom_response_valid && if_response_ready && !if_owner_ram) rom_response_valid<=0;
            if(io_response_valid && mem_response_ready && !data_owner_ram) io_response_valid<=0;
            if(if_valid && if_ready) begin
                if_owner_ram<=if_ram;
                if(!if_ram) begin
                    rom_response_valid<=1;
                    for(int n=0;n<3;n++) begin
                        rom_data[n*32+:32]<=rom_word(if_pc+32'(n*4));
                        rom_fault[n]<=if_pc+32'(n*4)>=32'h1000;
                    end
                end
            end
            if(mem_valid && mem_ready) begin
                data_owner_ram<=mem_ram; data_store<=mem_store;
                if(!mem_ram) begin
                    io_response_valid<=1;
                    io_data<=uart_selected?uart_data:timer_selected?timer_read_data:rom_word(mem_address);
                    io_fault<=!(uart_selected || timer_selected || (!mem_store && mem_address<32'h1000));
                end
            end
        end
    end
    initial begin
        assert(RAM_BASE[11:0]==0 && FDT_ADDRESS[11:0]==0) else $fatal(1,"Boot addresses must be page aligned");
    end
endmodule
