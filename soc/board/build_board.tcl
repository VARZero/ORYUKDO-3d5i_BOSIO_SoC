set here [file normalize [file dirname [info script]]]
set root [file normalize $here/../..]
set out [file normalize [lindex $argv 0]]
file mkdir $out
cd $out
set_param general.maxThreads 6
create_project -in_memory -part xc7a200tfbg484-2
read_ip [file normalize [lindex $argv 1]]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY XPM_FIFO} [current_project]
set fd [open $root/soc/bosio_sources.f]
foreach p [split [string trim [read $fd]] "\n"] {add_files -norecurse $root/[string trim $p]}
close $fd
foreach p {kfb_axi_mig.sv kfb_native_arbiter.sv kfb_video_fifo.sv kfb_video.sv kfb_hdmi.sv sd_boot.sv sd_reader.sv gen3_kfb_bosio.sv} {add_files -norecurse $here/$p}
foreach p {DVI_Constants.vhd SyncAsync.vhd SyncAsyncReset.vhd ClockGen.vhd TMDS_Encoder.vhd OutputSERDES.vhd rgb2dvi.vhd} {add_files -norecurse $here/vendor/digilent_rgb2dvi/src/$p}
foreach p {rgb2dvi.xdc rgb2dvi_clocks.xdc} {
    set vendor_xdc $here/vendor/digilent_rgb2dvi/src/$p
    add_files -fileset constrs_1 -norecurse $vendor_xdc
    set_property SCOPED_TO_REF rgb2dvi [get_files $vendor_xdc]
}
set_property PROCESSING_ORDER LATE [get_files $here/vendor/digilent_rgb2dvi/src/rgb2dvi_clocks.xdc]
foreach p {kfb.xdc sd.xdc peripherals.xdc} {add_files -fileset constrs_1 -norecurse $here/$p}
set_property top gen3_kfb_bosio [current_fileset]
update_compile_order -fileset sources_1
synth_design -top gen3_kfb_bosio -part xc7a200tfbg484-2 -flatten_hierarchy rebuilt
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]]} {error "Unfilled blackboxes"}
set first [get_cells -hier -regexp {.*(req_meta_reg|ack_meta_reg|lock_meta_reg|grant_meta_reg|data_meta_reg.*)}]
if {[llength $first]<5} {error "Missing preserved B/lock CDC synchronizers"}
set_false_path -to [get_pins -of_objects $first -filter {REF_PIN_NAME == D}]
set_false_path -from [get_ports rst_n]
# MIG 4.2 implements these four chains as asynchronous-assert, shift-zero-release
# reset synchronizers, but omits ASYNC_REG. Preserve and place the verified chains
# as synchronizers; do not replace MIG's reset sequencing or waive CDC checks.
set mig_resets [get_cells -hier -regexp {ddr/u_mig_7series_0_mig/(u_ddr3_infrastructure/(rstdiv0_sync_r|rstdiv2_sync_r|rst_sync_r).*reg.*|u_iodelay_ctrl/rst_ref_sync_r_reg.*)}]
if {[llength $mig_resets]<40} {error "Missing reviewed MIG reset synchronizers"}
set_property ASYNC_REG TRUE $mig_resets
set fd [open $out/mig_reset_cells.txt w];foreach cell $mig_resets {puts $fd $cell};close $fd
set cpu_clock [get_clocks -of_objects [get_pins cpu_buffer/O]]
set fabric_clock [get_clocks -of_objects [get_pins ddr/ui_clk]]
if {[llength $cpu_clock]!=1 || [llength $fabric_clock]!=1} {error "Missing board clocks"}
set_clock_uncertainty -setup 0.300 [concat $cpu_clock $fabric_clock]
set_property MAX_MESSAGES 100000 [get_drc_checks]
report_utilization -file $out/synth_utilization.rpt
report_utilization -hierarchical -file $out/synth_hierarchy.rpt
report_timing_summary -report_unconstrained -file $out/synth_timing.rpt
report_cdc -details -no_waiver -file $out/synth_cdc.rpt
report_clocks -file $out/clocks.rpt
report_io -file $out/io.rpt
write_checkpoint -force $out/synth.dcp
set cdc_rams [get_cells -hier -filter {(REF_NAME =~ RAMB*) && (NAME =~ system/cpu_crossing/*/transport/* || NAME =~ system/snoop_cdc/transport/* || NAME =~ display/scan_fifo/transport/*)}]
if {[llength $cdc_rams]<7} {error "Missing targeted CDC RAMs"}
set_power_opt -exclude_cells $cdc_rams
set fd [open $out/power_opt_excluded_cells.txt w];foreach ram $cdc_rams {puts $fd $ram};close $fd
opt_design
set protected_dsp [get_cells {system/bosio/projection1/ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_U33/bosio_projector_ama_addmuladd_16ns_17ns_8ns_16ns_24_4_1_DSP48_1_U/p_reg_reg}]
if {[llength $protected_dsp]!=1 || [get_property AREG $protected_dsp]<1} {error "Missing protected DSP pipeline"}
set_property DONT_TOUCH true $protected_dsp
report_drc -no_waivers -file $out/optimized_drc.rpt
write_checkpoint -force $out/optimized.dcp
report_cdc -details -no_waiver -file $out/optimized_cdc.rpt
set fd [open $out/optimized_cdc.rpt];set cdc [read $fd];close $fd
if {[regexp -line {^CDC-[0-9]+[ \t]+(Critical|Warning)[ \t]+[1-9][0-9]*[ \t]} $cdc]} {error "CDC warning/critical remains before placement"}
puts "PASS KFB_BOSIO_BOARD_SYNTHESIS"
close_project
