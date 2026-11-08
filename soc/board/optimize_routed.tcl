# Refine a fully routed checkpoint using supported post-route operations only.
# Preserve the best result; never change RTL, clock periods or timing exceptions.
if {[llength $argv]!=2} {error "Usage: optimize_routed.tcl routed.dcp output_directory"}
set here [file normalize [file dirname [info script]]]
set best_checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint $best_checkpoint
set_property MAX_MESSAGES 100000 [get_drc_checks]
set best_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set fd [open $out/physical_iterations.tsv w]
puts $fd "iteration\tdirective\tsetup_ns\thold_ns\tkept"
set iteration 0
foreach directive {Explore AggressiveExplore AlternateReplication Explore} {
    if {$best_setup>=0} {break}
    incr iteration
    phys_opt_design -directive $directive
    set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    report_timing -max_paths 10 -file $out/iteration_${iteration}_timing.rpt
    set keep [expr {$setup>$best_setup && $hold>=0}]
    puts $fd "$iteration\t$directive\t$setup\t$hold\t$keep"
    flush $fd
    if {$keep} {
        set best_setup $setup
        set best_checkpoint $out/best_${iteration}.dcp
        write_checkpoint -force $best_checkpoint
    } else {
        close_design
        open_checkpoint $best_checkpoint
        set_property MAX_MESSAGES 100000 [get_drc_checks]
    }
}
close $fd
set fd [open $here/route_board.tcl]
set base_script [read $fd]
close $fd
set offset [string first {write_checkpoint -force $out/routed.dcp} $base_script]
if {$offset<0} {error "Base final-report section changed"}
eval [string range $base_script $offset end]
