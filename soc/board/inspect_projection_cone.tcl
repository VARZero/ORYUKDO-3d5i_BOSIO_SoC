# Read-only inspection of the two DSP input cones with measured setup failures.
if {[llength $argv]!=2} {error "Usage: inspect_projection_cone.tcl routed.dcp output_directory"}
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint [file normalize [lindex $argv 0]]
set dsps [get_cells -hier -regexp {system/bosio/projection0/ama_addmuladd_.*_U(32|35)/.*/p_reg_reg}]
if {[llength $dsps]!=2} {error "Expected exactly the two failing DSPs"}
set apins {}
foreach p [get_pins -of_objects $dsps] {
    if {[regexp {^A\[[0-9]+\]$} [get_property REF_PIN_NAME $p]]} {lappend apins $p}
}
if {[llength $apins]!=60} {error "Expected 60 A-input bits"}
set cone [all_fanin -flat -only_cells -to $apins]
set fd [open $out/cone_cells.tsv w]
puts $fd "cell\tref\tloc\tbel\tsequential\tasync_reg\tdont_touch"
foreach c [lsort -unique $cone] {
    puts $fd "$c\t[get_property REF_NAME $c]\t[get_property LOC $c]\t[get_property BEL $c]\t[get_property IS_SEQUENTIAL $c]\t[get_property ASYNC_REG $c]\t[get_property DONT_TOUCH $c]"
}
close $fd
report_timing -to $apins -max_paths 20 -file $out/cone_timing.rpt
puts "PASS PROJECTION_CONE_INSPECTION cells=[llength $cone]"
