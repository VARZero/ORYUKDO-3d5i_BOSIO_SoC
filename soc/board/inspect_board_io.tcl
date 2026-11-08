# Read-only final-board inspection: explain I/O timing coverage and verify the
# selected arithmetic placement on the actual routed checkpoint.
if {[llength $argv]!=2} {error "Usage: inspect_board_io.tcl routed.dcp output_directory"}
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint [file normalize [lindex $argv 0]]
check_timing -verbose -override_defaults {no_input_delay no_output_delay partial_input_delay} -file $out/io_timing_coverage.rpt
set pb [get_pblocks projection0_input_arithmetic]
if {[llength $pb]!=1} {error "Missing selected arithmetic placement region"}
set cells [get_cells -of_objects $pb]
set fd [open $out/cluster_cells_routed.tsv w]
puts $fd "cell\tref\tloc"
foreach c $cells {
    set loc [get_property LOC $c]
    set ref [get_property REF_NAME $c]
    puts $fd "$c\t$ref\t$loc"
    if {$ref eq "DSP48E1"} {
        if {[string match *_U32/* $c]} {set target DSP48_X7Y86} else {set target DSP48_X7Y87}
        if {$loc ne $target || [get_property AREG $c]<1 || [get_property BREG $c]<1} {error "DSP placement or input pipeline changed"}
    } elseif {![regexp {^SLICE_X([0-9]+)Y([0-9]+)$} $loc unused x y] || $x<108 || $x>145 || $y<200 || $y>249} {
        error "Arithmetic cell outside the selected region: $c ($loc)"
    }
}
close $fd
puts "PASS ROUTED_CLUSTER_INSPECTION cells=[llength $cells]"
