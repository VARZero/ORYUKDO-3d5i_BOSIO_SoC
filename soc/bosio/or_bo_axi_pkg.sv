package or_bo_axi_pkg;
    // 32-bit data, one-bit transaction IDs, 64-bit addresses retained from HLS.
    // No address truncation: the fabric rejects addresses above the 32-bit map.
    typedef struct packed {
        logic id;
        logic [63:0] addr;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst,lock;
        logic [3:0] cache,qos,region;
        logic [2:0] prot;
        logic [3:0] user; // CPU ARUSER carries native read-byte enables for packed UART registers.
    } ax_addr_t;
    typedef struct packed {logic [31:0] data; logic [3:0] strb; logic last,id,user;} ax_w_t;
    typedef struct packed {logic [31:0] data; logic [1:0] resp; logic last,id,user;} ax_r_t;
    typedef struct packed {logic [1:0] resp; logic id,user;} ax_b_t;
    typedef struct packed {
        ax_addr_t aw,ar;
        ax_w_t w;
        logic awvalid,wvalid,bready,arvalid,rready;
    } ax_req_t;
    typedef struct packed {
        ax_b_t b;
        ax_r_t r;
        logic awready,wready,bvalid,arready,rvalid;
    } ax_rsp_t;
    typedef struct packed {
        logic [31:0] awaddr,araddr,wdata;
        logic [3:0] wstrb,rmask; // rmask is local sideband derived from AXI ARUSER, not an AXI-Lite channel.
        logic [2:0] awprot,arprot;
        logic awvalid,wvalid,bready,arvalid,rready;
    } al_req_t;
    typedef struct packed {
        logic [31:0] rdata;
        logic [1:0] bresp,rresp;
        logic awready,wready,bvalid,arready,rvalid;
    } al_rsp_t;
    localparam logic [1:0] OKAY=0,SLVERR=2,DECERR=3;
    // Lite: 0 system, 1 projection0, 2 projection1, 3 output0, 4 UART, 5 SPI, 6 I2C.
    localparam int LITE_PORTS=7;
    function automatic int target(input logic [63:0] address);
        if(address[63:32]!=0) return -1;
        if(address>=64'h80000000 && address<64'hc0000000) return 7;
        if(address>=64'h10004000 && address<64'h10004020) return 0;
        if(address>=64'h10005000 && address<64'h10005008) return 4;
        if(address>=64'h10006000 && address<64'h10006014) return 5;
        if(address>=64'h10007000 && address<64'h10007014) return 6;
        if(address>=64'h20000000 && address<64'h20000080) return 1;
        if(address>=64'h20010000 && address<64'h20010080) return 2;
        if(address>=64'h20020000 && address<64'h20020080) return 3;
        return -1;
    endfunction
    function automatic bit legal(input ax_addr_t a,input bit cpu);
        logic [12:0] last_offset;
        int t;
        t=target(a.addr);
        last_offset={1'b0,a.addr[11:0]}+{3'b0,a.len,2'b0}+13'd3;
        // Initial interconnect contract: aligned 32-bit INCR/FIXED, no exclusives.
        // CPU atomics use the explicit global lock, not AXI exclusive monitors.
        if(t<0 || a.size!=2 || a.addr[1:0]!=0 || a.lock!=0 || a.burst>1) return 0;
        if(a.burst==0 && a.len>15) return 0; // AXI4 FIXED bursts are limited to 16 beats.
        if(!cpu && t!=7) return 0;
        if(t!=7 && a.len!=0) return 0;
        // All burst-capable windows end on 4 KiB boundaries; other windows
        // accept only a single aligned word. No wide end-address adder needed.
        if(a.burst==1 && last_offset[12]) return 0;
        return 1;
    endfunction
endpackage
