# Alternative physical implementation for the observed full-board congestion.
# RTL, clock periods, setup reserve, DRC and CDC acceptance checks stay identical.
set fd [open [file join [file dirname [info script]] route_board.tcl]]
set route_script [read $fd]
close $fd
set route_script [string map [list "\nplace_design\n" "\nplace_design -directive AltSpreadLogic_high\n" "\nroute_design\n" "\nroute_design -directive Explore\n"] $route_script]
eval $route_script
