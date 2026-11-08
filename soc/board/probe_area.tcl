# Compare a tool-only area optimization of the same synthesized RTL.
# This is a diagnostic checkpoint, not an accepted implementation or bitstream.
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 4
open_checkpoint [file normalize [lindex $argv 0]]
set protected [get_cells -hier -filter {NAME =~ system/bosio/projection1/ama_addmuladd*U32/*/p_reg_reg || NAME =~ system/bosio/projection1/ama_addmuladd*U33/*/p_reg_reg || NAME =~ system/bosio/projection1/ama_addmuladd*U35/*/p_reg_reg}]
if {[llength $protected]!=3} {error "Missing reviewed DSP pipelines"}
foreach cell $protected {
    if {[get_property AREG $cell]<1 || [get_property BREG $cell]<1} {error "Missing DSP input register"}
}
set_property DONT_TOUCH true $protected
report_utilization -file $out/before_utilization.rpt
opt_design -directive ExploreArea
report_utilization -file $out/area_utilization.rpt
report_utilization -hierarchical -file $out/area_hierarchy.rpt
report_cdc -details -no_waiver -file $out/area_cdc.rpt
report_drc -no_waivers -file $out/area_drc.rpt
write_checkpoint -force $out/area.dcp
puts "PASS KFB_AREA_PROBE_ONLY"
close_project
