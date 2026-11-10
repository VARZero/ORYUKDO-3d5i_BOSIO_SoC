# Native SD is source synchronous. Verify the implemented pad-register and
# clock-enable timing model, not just global WNS or an unconstrained port.
set sd_inputs [get_cells -hier -regexp {storage/phy/(cmd_sample_reg|dat_sample_reg\[[0-3]\])}]
if {[llength $sd_inputs]!=5} {error "Expected five SD input pad registers"}
set fd [open $out/sd_pad_registers.tsv w]
foreach cell $sd_inputs {
 set loc [get_property LOC $cell]
 if {![string match ILOGIC* $loc]} {error "SD input not in pad register: $cell $loc"}
 puts $fd "$cell\t$loc\t[get_property BEL $cell]"
}
close $fd
foreach direction {input output} {
 foreach delay {max min} {
  if {$direction eq "input"} {
   set paths [get_timing_paths -from [get_ports {sd_cmd sd_dat[*]}] -delay_type $delay -max_paths 20]
   report_timing -from [get_ports {sd_cmd sd_dat[*]}] -delay_type $delay -max_paths 20 -path_type full_clock_expanded -file $out/sd_${direction}_${delay}.rpt
   set expected [expr {$delay eq "max" ? 30.0 : -10.0}]
  } else {
   set paths [get_timing_paths -to [get_ports {sd_cmd sd_dat[*]}] -delay_type $delay -max_paths 20]
   report_timing -to [get_ports {sd_cmd sd_dat[*]}] -delay_type $delay -max_paths 20 -path_type full_clock_expanded -file $out/sd_${direction}_${delay}.rpt
   set expected [expr {$delay eq "max" ? 20.0 : -20.0}]
  }
  if {[llength $paths]<5} {error "Missing native SD timing paths: $direction $delay"}
  foreach path $paths {
   if {abs([get_property REQUIREMENT $path]-$expected)>0.001} {error "Wrong SD phase constraint: $direction $delay $path"}
   if {[get_property SLACK $path]<0} {error "SD pin timing failed: $direction $delay $path"}
  }
 }
}
puts "PASS NATIVE_SD_PAD_AND_PHASE_TIMING_AUDIT"
