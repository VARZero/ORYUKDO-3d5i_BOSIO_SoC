set out [file normalize [lindex $argv 1]]
file mkdir $out
open_checkpoint [file normalize [lindex $argv 0]]
if {[llength $argv]>2 && [lindex $argv 2] eq "opt"} {opt_design}
report_cdc -details -file $out/cdc.rpt
set f [open $out/response_registers.txt w]
foreach cell [get_cells -hier -filter {NAME =~ cpu_crossing/b/* && IS_SEQUENTIAL == 1}] {
    puts $f "$cell [get_property REF_NAME $cell] ASYNC_REG=[get_property ASYNC_REG $cell]"
}
close $f
