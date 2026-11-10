# Read-only inspection of an immutable routed checkpoint, including a failed one.
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint $checkpoint
report_timing_summary -report_unconstrained -file $out/timing_summary.rpt
report_timing -delay_type max -max_paths 50 -file $out/setup_paths.rpt
report_timing -delay_type min -max_paths 10 -file $out/hold_paths.rpt
report_utilization -file $out/utilization.rpt
report_utilization -hierarchical -file $out/hierarchy.rpt
foreach clock {cpu_raw clk_pll_i pixel_raw serial_raw} {
    report_timing -from [get_clocks $clock] -to [get_clocks $clock] -max_paths 10 -file $out/timing_$clock.rpt
}
report_drc -no_waivers -file $out/drc.rpt
puts "DONE KFB_CHECKPOINT_INSPECTION_ONLY"
close_project
