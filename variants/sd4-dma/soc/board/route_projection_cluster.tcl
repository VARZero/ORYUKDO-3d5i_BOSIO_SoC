# Cluster only the measured U32/U35 A-input cones near their operand registers.
# Source RTL/IP and all timing constraints remain unchanged.
if {[llength $argv]!=3} {error "Usage: route_projection_cluster.tcl placed.dcp routed_reference.dcp output_directory"}
set here [file normalize [file dirname [info script]]]
set reference [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
file mkdir $out
cd $out
set_param general.maxThreads 6
open_checkpoint [file normalize [lindex $argv 0]]
set_property MAX_MESSAGES 100000 [get_drc_checks]
set dsps [get_cells -hier -regexp {system/bosio/projection0/ama_addmuladd_.*_U(32|35)/.*/p_reg_reg}]
if {[llength $dsps]!=2} {error "Expected exactly the two measured DSP endpoints"}
set apins {}
foreach p [get_pins -of_objects $dsps] {
    if {[regexp {^A\[[0-9]+\]$} [get_property REF_PIN_NAME $p]]} {lappend apins $p}
}
if {[llength $apins]!=60} {error "Expected 60 A-input pins"}
set cone [all_fanin -flat -only_cells -to $apins]
if {[llength $cone]<300 || [llength $cone]>400} {error "Unexpected arithmetic cone size"}
set fd [open $out/cluster_cells_before.tsv w]
puts $fd "cell\tref\tloc"
foreach c $cone {
    set ref [get_property REF_NAME $c]
    if {![regexp {^(LUT[1-6]|CARRY4|FDRE|DSP48E1)$} $ref] ||
        [get_property ASYNC_REG $c] in {1 true TRUE}} {
        error "Unexpected cell in arithmetic cone: $c ($ref)"
    }
    puts $fd "$c\t$ref\t[get_property LOC $c]"
}
close $fd
# Read-only site inspection found this adjacent cascade pair unoccupied. It is
# beside the source-register cluster, unlike the original distant X2 pair.
set targets {}
foreach d $dsps {
    if {[string match *_U32/* $d]} {set target DSP48_X7Y86} else {set target DSP48_X7Y87}
    set occupants [get_cells -quiet -of_objects [get_sites $target]]
    if {[llength $occupants]!=0} {error "Inspected DSP site is no longer free: $target ($occupants)"}
    if {[get_property AREG $d]<1 || [get_property BREG $d]<1} {error "Missing DSP input pipeline"}
    lappend targets $d $target
}
# Check both sites first: moving the first member can automatically relocate
# the second member of this dedicated PCOUT/PCIN cascade.
foreach {d target} $targets {
    set_property LOC $target $d
    set_property IS_LOC_FIXED true $d
}
set pb [create_pblock projection0_input_arithmetic]
add_cells_to_pblock $pb $cone
resize_pblock $pb -add {SLICE_X108Y200:SLICE_X145Y249 DSP48_X7Y86:DSP48_X7Y87}
set_property IS_SOFT false $pb
read_checkpoint -incremental -directive TimingClosure $reference
set logic_cone [filter $cone {REF_NAME != DSP48E1}]
unplace_cell $logic_cone
foreach c $logic_cone {
    if {[get_property LOC $c] ne ""} {error "Arithmetic cell was not unplaced: $c"}
}
report_incremental_reuse -file $out/incremental_reuse.rpt
place_design
proc audit_cluster_placement {out suffix} {
    set fd [open $out/cluster_cells_${suffix}.tsv w]
    puts $fd "cell\tref\tloc"
    set cells [get_cells -of_objects [get_pblocks projection0_input_arithmetic]]
    if {[llength $cells]<300 || [llength $cells]>500} {error "Unexpected placed cone size"}
    foreach c $cells {
        set ref [get_property REF_NAME $c]
        set loc [get_property LOC $c]
        puts $fd "$c\t$ref\t$loc"
        if {$ref eq "DSP48E1"} {
            if {[string match *_U32/* $c]} {set target DSP48_X7Y86} else {set target DSP48_X7Y87}
            if {$loc ne $target} {error "DSP cascade placement was not applied: $c ($loc)"}
        } elseif {![regexp {^SLICE_X([0-9]+)Y([0-9]+)$} $loc unused x y] ||
                  $x<108 || $x>145 || $y<200 || $y>249} {
            error "Arithmetic cell outside the selected region: $c ($loc)"
        }
    }
    close $fd
    puts "PASS PROJECTION_CLUSTER_PLACEMENT stage=$suffix cells=[llength $cells]"
}
audit_cluster_placement $out placed
phys_opt_design
audit_cluster_placement $out optimized
report_drc -no_waivers -file $out/cluster_placed_drc.rpt
set fd [open $out/cluster_placed_drc.rpt];set drc [read $fd];close $fd
if {[regexp -line {^(NSTD-1|UCIO-1|DPIP-1|DPOP-1|DPOP-2|REQP-1839|REQP-1840|RBOR-1)#[0-9]+} $drc]} {error "User logic/pin DRC in clustered placement"}
write_checkpoint -force $out/cluster_placed.dcp
report_timing -max_paths 10 -file $out/cluster_placed_timing.rpt
route_design -directive Explore -tns_cleanup
write_checkpoint -force $out/routed_initial.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]<0} {phys_opt_design -directive AggressiveExplore}
set fd [open $here/route_board.tcl]
set base_script [read $fd]
close $fd
set offset [string first {write_checkpoint -force $out/routed.dcp} $base_script]
if {$offset<0} {error "Base final-report section changed"}
eval [string range $base_script $offset end]
