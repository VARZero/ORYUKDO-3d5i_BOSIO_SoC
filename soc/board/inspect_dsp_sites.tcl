# Read-only physical inventory for the two failing projection0 DSPs.
if {[llength $argv]!=2} {error "Usage: inspect_dsp_sites.tcl routed.dcp output_directory"}
set out [file normalize [lindex $argv 1]]
file mkdir $out
cd $out
set_param general.maxThreads 2
open_checkpoint [file normalize [lindex $argv 0]]
set fd [open $out/dsp_sites.tsv w]
puts $fd "site\ttile_x\ttile_y\toccupant"
foreach s [get_sites -filter {SITE_TYPE == DSP48E1}] {
    if {![regexp {Y(8[4-9]|90)$} $s]} {continue}
    set tile [get_tiles -of_objects $s]
    puts $fd "$s\t[get_property GRID_POINT_X $tile]\t[get_property GRID_POINT_Y $tile]\t[get_cells -of_objects $s]"
}
close $fd
set fd [open $out/dsp_neighbors.tsv w]
puts $fd "dsp\tpin\tcell\tref\tloc"
foreach d [get_cells -hier -regexp {system/bosio/projection0/ama_addmuladd_.*_U(32|35)/.*/p_reg_reg}] {
    foreach p [get_pins -of_objects $d -filter {DIRECTION == OUT}] {
        foreach c [get_cells -of_objects [all_fanout -flat -endpoints_only -from $p]] {
            puts $fd "$d\t[get_property REF_PIN_NAME $p]\t$c\t[get_property REF_NAME $c]\t[get_property LOC $c]"
        }
    }
}
close $fd
set source_site [get_sites SLICE_X118Y227]
set tile [get_tiles -of_objects $source_site]
puts "SOURCE_SITE $source_site TILE_X=[get_property GRID_POINT_X $tile] TILE_Y=[get_property GRID_POINT_Y $tile]"
puts "PASS DSP_SITE_INSPECTION"
