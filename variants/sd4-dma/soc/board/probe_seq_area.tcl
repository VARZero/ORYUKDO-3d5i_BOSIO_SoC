# Diagnostic second-stage tool optimization. No RTL or IP source modifications.
# The input is the previously preserved ExploreArea checkpoint.
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint [file normalize [lindex $argv 0]]
report_utilization -file $out/before_utilization.rpt
opt_design -directive ExploreSequentialArea
report_utilization -file $out/area_utilization.rpt
report_utilization -hierarchical -file $out/area_hierarchy.rpt
report_cdc -details -no_waiver -file $out/area_cdc.rpt
report_drc -no_waivers -file $out/area_drc.rpt
write_checkpoint -force $out/area_seq.dcp
puts "PASS KFB_SEQUENTIAL_AREA_PROBE_ONLY"
close_project
