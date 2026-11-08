set out [file normalize [lindex $argv 1]]
file mkdir $out
open_checkpoint [lindex $argv 0]
report_cdc -details -no_waiver -file $out/cdc_no_waiver.rpt
report_cdc -details -show_waiver -file $out/cdc_show_waiver.rpt
set sources [get_cells -hier -filter {NAME =~ */src_gray_ff_reg* && IS_SEQUENTIAL == 1}]
set all_dests [get_cells -hier -filter {NAME =~ */dest_graysync_ff_reg* && IS_SEQUENTIAL == 1}]
set fd [open $out/gray_paths.tsv w]
puts $fd "start\tend\trequirement\tdelay\tslack\tasync_reg\texception"
set count 0
foreach dest $all_dests {
    if {![regexp {dest_graysync_ff_reg\[0\]} $dest]} {continue}
    set pin [get_pins -of_objects $dest -filter {REF_PIN_NAME == D}]
    set paths [get_timing_paths -from $sources -to $pin -delay_type max -max_paths 1]
    if {[llength $paths]!=1} {error "Missing Gray pointer timing: $pin"}
    set p [lindex $paths 0]
    set req [get_property REQUIREMENT $p]
    set slack [get_property SLACK $p]
    set clock [get_property STARTPOINT_CLOCK $p]
    set period [get_property PERIOD $clock]
    set async [get_property ASYNC_REG $dest]
    puts $fd "[get_property STARTPOINT_PIN $p]\t[get_property ENDPOINT_PIN $p]\t$req\t[get_property DATAPATH_DELAY $p]\t$slack\t$async\t[get_property EXCEPTION $p]"
    if {abs($req-$period)>0.001 || $slack<0 || !$async} {error "Gray CDC constraint/synchronizer check failed: $pin"}
    incr count
}
close $fd
if {$count<40} {error "Expected at least 40 Gray-pointer first-stage bits, found $count"}
report_timing -from $sources -to $all_dests -max_paths 100 -file $out/gray_timing.rpt
puts "PASS XPM_ROUTED_AUDIT gray_bits=$count"
