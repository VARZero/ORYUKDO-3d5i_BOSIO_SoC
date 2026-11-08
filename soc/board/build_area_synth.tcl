# Isolated synthesis experiment for the observed full-board routing congestion.
# Same RTL, IP sources, clock periods, setup reserve and acceptance checks.
set fd [open [file join [file dirname [info script]] build_board.tcl]]
set build_script [read $fd]
close $fd
set original {synth_design -top gen3_kfb_bosio -part xc7a200tfbg484-2 -flatten_hierarchy rebuilt}
if {[string first $original $build_script]<0} {error "Base synthesis command changed"}
set build_script [string map [list $original "$original -directive AreaOptimized_high" {set_param general.maxThreads 6} {set_param general.maxThreads 2}] $build_script]
eval $build_script
