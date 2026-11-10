# Run on the current routed design, with $out set by route_board.tcl.
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
    set period [get_property PERIOD [get_property STARTPOINT_CLOCK $p]]
    set async [get_property ASYNC_REG $dest]
    puts $fd "[get_property STARTPOINT_PIN $p]\t[get_property ENDPOINT_PIN $p]\t$req\t[get_property DATAPATH_DELAY $p]\t$slack\t$async\t[get_property EXCEPTION $p]"
    if {abs($req-$period)>0.001 || $slack<0 || !$async} {error "Gray CDC constraint failed: $pin"}
    incr count
}
close $fd
if {$count<58} {error "Expected at least 58 CPU/display Gray-pointer bits, found $count"}
set fd [open $out/bus_skew.rpt];set skew [read $fd];close $fd
if {[string first "VIOLATED" $skew]>=0} {error "Routed Gray bus skew failed"}
set fd [open $out/cdc.rpt];set cdc [read $fd];close $fd
if {[regexp -line {^CDC-[0-9]+[ \t]+(Critical|Warning)[ \t]+[1-9][0-9]*[ \t]} $cdc]} {error "CDC warning/critical remains"}
set fd [open $out/drc.rpt];set drc [read $fd];close $fd
if {[regexp -line {^(NSTD-1|UCIO-1|DPIP-1|DPOP-1|DPOP-2|REQP-1839|REQP-1840|RBOR-1)#[0-9]+} $drc]} {error "User logic DRC reappeared after routing"}
set fd [open $out/dsp_registers.tsv w]
puts $fd "cell\tAREG\tBREG\tMREG\tPREG"
foreach d [get_cells -hier -filter {REF_NAME == DSP48E1}] {
    puts $fd "$d\t[get_property AREG $d]\t[get_property BREG $d]\t[get_property MREG $d]\t[get_property PREG $d]"
}
close $fd
if {![report_route_status -boolean_check ROUTED_FULLY -ignore_cache] ||
    [report_route_status -boolean_check ERRORS_IN_ROUTES -ignore_cache]} {
    error "Routed audit failed: incomplete or conflicting routing"
}
if {[regexp {\|[^\n|]+\|[ \t]+(Error|Critical Warning)[ \t]+\|} $drc]} {
    error "Routed audit failed: DRC Error/Critical Warning"
}
puts "PASS KFB_BOARD_ROUTED_AUDIT gray_bits=$count"
