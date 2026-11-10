# First perform the unchanged routed Gray-pointer/CDC audit.
source [file join [file dirname [info script]] audit_xpm_routed.tcl]
set from_cells [get_cells -hier -filter {NAME =~ */u_display_transform/out_data_reg* && IS_SEQUENTIAL == 1}]
set bank_cells [get_cells -hier -filter {NAME =~ */u_projector/cfg_bank*data_reg* && IS_SEQUENTIAL == 1}]
set shadow_cells [get_cells -hier -filter {NAME =~ */u_projector/*shadow_reg* && IS_SEQUENTIAL == 1}]
if {[llength $from_cells]==0 || [llength $bank_cells]==0 || [llength $shadow_cells]==0} {error "Missing registered configuration bank timing endpoints"}
report_timing -from $from_cells -to $bank_cells -max_paths 10 -file $out/config_to_banks.rpt
report_timing -from $bank_cells -to $shadow_cells -max_paths 10 -file $out/banks_to_shadow.rpt
set fd [open $out/dsp_registers.tsv w]
puts $fd "cell\tAREG\tBREG\tMREG\tPREG"
foreach d [get_cells -hier -filter {REF_NAME == DSP48E1}] {
    puts $fd "$d\t[get_property AREG $d]\t[get_property BREG $d]\t[get_property MREG $d]\t[get_property PREG $d]"
}
close $fd
puts "PASS REGISTERED_BANK_AUDIT bank_bits=[llength $bank_cells]"
