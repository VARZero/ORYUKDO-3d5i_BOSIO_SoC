# Incremental physical optimization of the five measured remaining setup paths.
# Arguments: placed checkpoint, routed reference checkpoint, output directory.
# Forced replication is a POST-PLACE operation in Vivado 2022.2; it is not
# supported in post-route mode. Reuse completed routing after replication.
# No vendor RTL, cycle latency, reset architecture or timing exceptions change.
if {[llength $argv]!=3} {error "Usage: refine_route.tcl placed.dcp routed_reference.dcp output_directory"}
set here [file normalize [file dirname [info script]]]
set reference [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
file mkdir $out
cd $out
set_param general.maxThreads 6
open_checkpoint [file normalize [lindex $argv 0]]
set_property MAX_MESSAGES 100000 [get_drc_checks]
# These two operand registers are the sources of all five failing paths in
# area_medium_guarded_v1. Replication is limited to their 17 ordinary FF bits.
set cells [get_cells -hier -regexp {system/bosio/projection0/(sub_ln10_reg_3124_reg|trunc_ln1_reg_3062_reg)\[[0-9]+\]}]
if {[llength $cells]<2 || [llength $cells]>17} {error "Unexpected operand register selection"}
set nets {}
set fd [open $out/replication_targets.tsv w]
puts $fd "cell\tnet"
foreach cell $cells {
    if {![string match FD* [get_property REF_NAME $cell]] ||
        [string equal -nocase [get_property ASYNC_REG $cell] true] ||
        [string equal -nocase [get_property DONT_TOUCH $cell] true]} {
        error "Replication target is not an ordinary unprotected operand FF: $cell"
    }
    set q [get_pins -of_objects $cell -filter {REF_PIN_NAME == Q && DIRECTION == OUT}]
    if {[llength $q]!=1} {error "Missing operand register Q pin: $cell"}
    foreach net [get_nets -of_objects $q] {
        lappend nets $net
        puts $fd "$cell\t$net"
    }
}
close $fd
set nets [lsort -unique $nets]
if {[llength $nets]<2} {error "Missing operand nets"}
phys_opt_design -force_replication_on_nets $nets
write_checkpoint -force $out/replicated_placed.dcp
read_checkpoint -incremental -directive TimingClosure $reference
report_incremental_reuse -file $out/incremental_reuse.rpt
place_design
# Check the affected DSP pipelines before entering routing again.
report_drc -no_waivers -file $out/incremental_placed_drc.rpt
set fd [open $out/incremental_placed_drc.rpt];set drc [read $fd];close $fd
if {[regexp -line {^(NSTD-1|UCIO-1|DPIP-1|DPOP-1|DPOP-2|REQP-1839|REQP-1840|RBOR-1)#[0-9]+} $drc]} {
    error "User logic/pin DRC in incremental placement"
}
write_checkpoint -force $out/incremental_placed.dcp
route_design -directive Explore -tns_cleanup
write_checkpoint -force $out/routed_initial.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]<0} {
    phys_opt_design -directive AggressiveExplore
}
# Use exactly the same final reports, CDC/DRC audit and bitstream timing gates.
set fd [open $here/route_board.tcl]
set base_script [read $fd]
close $fd
set marker {write_checkpoint -force $out/routed.dcp}
set offset [string first $marker $base_script]
if {$offset<0} {error "Base final-report section changed"}
eval [string range $base_script $offset end]
