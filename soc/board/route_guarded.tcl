# Preserve only the DSPs whose input registers were actually unpacked in the
# full-board placement logs (official_v6/spread and area_medium_synth_v1).
# Vendor RTL, pipeline latency, clock periods and timing acceptance are unchanged.
set here [file normalize [file dirname [info script]]]
set fd [open $here/route_board.tcl]
set route_script [read $fd]
close $fd
set anchor {# The unmodified official encoder}
if {[string first $anchor $route_script]<0} {error "Base route preflight changed"}
set protection {
foreach projection {0 1} {
    foreach unit {32 33 34 35 36 37} {
        if {$unit<35} {
            set shape {16ns_17ns_8ns_16ns_24_4_1}
            set dsp_kind 1
        } else {
            set shape {16ns_17ns_9ns_24ns_24_4_1}
            set dsp_kind 2
        }
        set path "system/bosio/projection${projection}/ama_addmuladd_${shape}_U${unit}/bosio_projector_ama_addmuladd_${shape}_DSP48_${dsp_kind}_U/p_reg_reg"
        set cell [get_cells $path]
        if {[llength $cell]!=1 || [get_property AREG $cell]<1 || [get_property BREG $cell]<1} {
            error "Missing observed DSP input pipeline: $path"
        }
        set_property DONT_TOUCH true $cell
    }
}
}
set stages {place_design
phys_opt_design
route_design}
if {[string first $stages $route_script]<0} {error "Base implementation stages changed"}
set guarded_stages {
proc check_pipeline_drc {out stage} {
    report_drc -no_waivers -file $out/${stage}_drc.rpt
    set fd [open $out/${stage}_drc.rpt];set report [read $fd];close $fd
    if {[regexp -line {^(NSTD-1|UCIO-1|DPIP-1|DPOP-1|DPOP-2|REQP-1839|REQP-1840|RBOR-1)#[0-9]+} $report]} {
        error "User logic/pin DRC at $stage; do not start a long route"
    }
}
place_design
write_checkpoint -force $out/placed.dcp
check_pipeline_drc $out placed
phys_opt_design
write_checkpoint -force $out/placed_optimized.dcp
check_pipeline_drc $out placed_optimized
route_design
}
set route_script [string map [list $anchor "$protection\n$anchor" $stages $guarded_stages] $route_script]
eval $route_script
