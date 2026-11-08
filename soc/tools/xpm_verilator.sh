# Source from the SoC root. No replacement model of the XPM transport.
XPM_ROOT="${XPM_ROOT:-/mnt/d/Xilinx2202/Vivado/2022.2/data/ip/xpm}"
XPM_ARGS=(--bbox-unsup -DOBSOLETE -DDISABLE_XPM_ASSERTIONS -DONESPIN
 "$XPM_ROOT/xpm_cdc/hdl/xpm_cdc.sv"
 "$XPM_ROOT/xpm_memory/hdl/xpm_memory.sv"
 "$XPM_ROOT/xpm_fifo/hdl/xpm_fifo.sv")
