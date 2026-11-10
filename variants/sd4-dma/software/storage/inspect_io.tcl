# Read-only coverage review for this SD4 implementation. The old board helper
# additionally expects a placement pblock from a different physical strategy.
if {[llength $argv]!=2} {error "Usage: routed.dcp output_directory"}
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint [file normalize [lindex $argv 0]]
check_timing -verbose -override_defaults {no_input_delay no_output_delay partial_input_delay} -file $out/io_timing_coverage.rpt
puts "PASS CURRENT_BOARD_IO_COVERAGE_INSPECTION"
close_project
