set here [file normalize [file dirname [info script]]]
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 6
open_checkpoint [file normalize [lindex $argv 0]]
set_property MAX_MESSAGES 100000 [get_drc_checks]
# The first full-board placement additionally unpacked U32 and U35 (18 input
# registers each). Preserve only those observed DSPs, alongside the original U33.
foreach path {
 system/bosio/projection1/ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_U32/bosio_projector_ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_DSP48_1_U/p_reg_reg
 system/bosio/projection1/ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_U33/bosio_projector_ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_DSP48_1_U/p_reg_reg
 system/bosio/projection1/ama_addmuladd_16ns_17ns_9ns_24ns_24_4_1_U35/bosio_projector_ama_addmuladd_16ns_17ns_9ns_24ns_24_4_1_DSP48_2_U/p_reg_reg
} {
    set cell [get_cells $path]
    if {[llength $cell]!=1 || [get_property AREG $cell]<1 || [get_property BREG $cell]<1} {error "Missing dedicated DSP input registers: $path"}
    set_property DONT_TOUCH true $cell
}
# The unmodified official encoder has no added reset pins. Its registers and
# the external adapter's reset source must all belong to the pixel domain.
set encoder_cells [get_cells -hier -filter {NAME =~ hdmi_output/transmitter/*.DataEncoder/* && IS_SEQUENTIAL == 1}]
if {[llength $encoder_cells]<30} {error "Missing official encoder registers"}
set reset_source [get_cells hdmi_output/pixel_run_reg]
if {[llength $reset_source]!=1} {error "Missing external HDMI reset source"}
set fd [open $out/hdmi_pixel_domain.tsv w]
foreach cell [concat $encoder_cells $reset_source] {
    set clocks [get_clocks -of_objects [get_pins -of_objects $cell -filter {REF_PIN_NAME == C}]]
    if {[llength $clocks]!=1 || [lindex $clocks 0] ne "pixel_raw"} {error "HDMI register outside pixel domain: $cell ($clocks)"}
    puts $fd "$cell\t$clocks"
}
close $fd
# These are asynchronous pins with explicit first-stage synchronizers, not
# synchronous external buses. Bound FPGA pad propagation without inventing a
# board/device launch clock. External module timing still needs board validation.
set fd [open $out/input_synchronizers.tsv w]
foreach port {uart_rx gp_uart_rx gp_spi_miso gp_i2c_scl gp_i2c_sda sensor_scl sensor_sda} {
    set ends [all_fanout -flat -endpoints_only -from [get_ports $port]]
    if {[llength $ends]!=1} {error "Unexpected input fanout for $port: $ends"}
    set cell [get_cells -of_objects $ends]
    if {![get_property ASYNC_REG $cell]} {error "Input lacks preserved synchronizer: $port $cell"}
    set_max_delay -datapath_only 12 -from [get_ports $port] -to $ends
    puts $fd "$port\t$cell"
}
close $fd
# SPI half-period is at least 80 ns. I2C can wait for its sampled line state;
# UART holds each bit for thousands of clocks. These bounds limit local skew.
foreach port {uart_tx gp_uart_tx gp_spi_sck gp_spi_mosi gp_spi_cs_n gp_i2c_scl gp_i2c_sda sensor_scl sensor_sda error} {
    set starts [get_cells -of_objects [all_fanin -flat -startpoints_only -to [get_ports $port]] -filter {IS_SEQUENTIAL == 1}]
    if {[llength $starts]==0} {error "Missing output launch registers: $port"}
    set_max_delay -datapath_only 12 -from $starts -to [get_ports $port]
}
# TMDS uses the example's dedicated OSERDESE2/OBUFDS paths. Preserve the tool's
# native pixel/serializer clock checks. Do not segment OQ timing arcs or invent
# a receiver output-delay budget absent from the schematic/PCB information.
report_drc -no_waivers -file $out/preplace_drc.rpt
set fd [open $out/preplace_drc.rpt];set drc [read $fd];close $fd
if {[regexp -line {^(NSTD-1|UCIO-1|DPIP-1|DPOP-1|DPOP-2|REQP-1839|REQP-1840|RBOR-1)#[0-9]+} $drc]} {error "User logic/pin DRC remains"}
if {[lindex $argv 2] eq "check-only"} {
    write_checkpoint -force $out/constrained.dcp
    puts "PASS KFB_BOARD_PREFLIGHT"
    exit
}
place_design
phys_opt_design
route_design
write_checkpoint -force $out/routed_initial.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]<0} {phys_opt_design -directive AggressiveExplore}
write_checkpoint -force $out/routed.dcp
report_utilization -file $out/utilization.rpt
report_utilization -hierarchical -file $out/hierarchy.rpt
report_timing_summary -report_unconstrained -file $out/timing_routed.rpt
report_route_status -file $out/route_status.rpt
report_clocks -file $out/clocks.rpt
report_io -file $out/io.rpt
foreach clock {cpu_raw clk_pll_i pixel_raw serial_raw} {
    report_timing -from [get_clocks $clock] -to [get_clocks $clock] -max_paths 10 -file $out/timing_$clock.rpt
}
report_bus_skew -file $out/bus_skew.rpt
report_cdc -details -no_waiver -file $out/cdc.rpt
report_exceptions -coverage -file $out/exception_coverage.rpt
report_waivers -file $out/waivers.rpt
report_drc -no_waivers -file $out/drc.rpt
write_xdc -force $out/resolved_constraints.xdc
source $here/audit_board.tcl
source $here/audit_sd_io.tcl
# Keep failing results reviewable. Bitstream generation requires both setup and hold.
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$setup<0 || $hold<0} {error "Routed timing failed: setup=$setup hold=$hold"}
write_bitstream -force $out/ORYUKDO-Gen3-BOSIO-KFB.bit
puts "PASS KFB_BOSIO_BOARD_ROUTE setup=$setup hold=$hold"
