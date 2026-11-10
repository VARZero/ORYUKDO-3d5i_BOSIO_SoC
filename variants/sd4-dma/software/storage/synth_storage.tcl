set root [file normalize [file join [file dirname [info script]] ../..]]
set out [file normalize [lindex $argv 0]]
file mkdir $out
cd $out
set_param general.maxThreads 4
create_project -in_memory -part xc7a200tfbg484-2
foreach file {or_bo_axi_pkg.sv gen3_axil_regs.sv or_sd_native.sv or_storage_dma.sv or_sd_storage.sv} {
 read_verilog -sv $root/soc/bosio/$file
}
synth_design -mode out_of_context -top or_sd_storage -part xc7a200tfbg484-2
create_clock -name fabric -period 10.000 [get_ports clk]
set_clock_uncertainty 0.300 [get_clocks fabric]
report_utilization -hierarchical -file $out/synth_utilization.rpt
report_timing_summary -report_unconstrained -file $out/synth_timing.rpt
write_checkpoint -force $out/synth.dcp
opt_design
place_design
phys_opt_design
route_design
report_utilization -hierarchical -file $out/route_utilization.rpt
report_timing_summary -report_unconstrained -file $out/route_timing.rpt
report_drc -no_waivers -file $out/route_drc.rpt
write_checkpoint -force $out/routed.dcp
puts "STORAGE_OOC_IMPLEMENTATION_FINISHED: internal paths only, no board I/O timing claim"
