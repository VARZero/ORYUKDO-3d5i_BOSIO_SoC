# Reuse the accepted full-board placement/routing after the CPU bridge fix.
# All guarded DSP checks, clock constraints and final routed audits are retained.
if {[llength $argv]!=3} {error "Usage: optimized.dcp output_directory reference_routed.dcp"}
set reference [file normalize [lindex $argv 2]]
if {![file exists $reference]} {error "Missing routed reference"}
set here [file normalize [file dirname [info script]]]
set fd [open $here/route_guarded.tcl];set guarded [read $fd];close $fd
set anchor {place_design
write_checkpoint -force $out/placed.dcp}
if {[string first $anchor $guarded]<0} {error "Guarded placement stage changed"}
set replacement {read_checkpoint -incremental $reference
place_design
write_checkpoint -force $out/placed.dcp}
set guarded [string map [list $anchor $replacement] $guarded]
eval $guarded
