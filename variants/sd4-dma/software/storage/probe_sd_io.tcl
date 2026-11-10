set here [file normalize [file dirname [info script]]]
set root [file normalize $here/../..]
set out [file normalize [lindex $argv 0]]
file mkdir $out
cd $out
create_project -in_memory -part xc7a200tfbg484-2
set_param general.maxThreads 4
read_verilog -sv $root/soc/bosio/or_sd_native.sv
read_verilog -sv $here/sd_io_probe.sv
synth_design -top sd_io_probe -part xc7a200tfbg484-2
create_clock -name board200 -period 5.000 [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL135} [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL135 [get_ports sys_clk_n]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports rst_n]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports error]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set f [open $root/soc/board/sd.xdc];set constraints [read $f];close $f
eval [string map {ddr/ui_clk fabric_clock/O} $constraints]
set_false_path -from [get_ports rst_n]
set_max_delay -datapath_only 12 -from [get_cells result_reg] -to [get_ports error]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file $out/utilization.rpt
report_timing_summary -report_unconstrained -file $out/timing.rpt
foreach direction {input output} {
 foreach delay {max min} {
  if {$direction eq "input"} {
   report_timing -delay_type $delay -from [get_ports {sd_cmd sd_dat[*]}] -max_paths 20 -path_type full_clock_expanded -file $out/${direction}_${delay}.rpt
  } else {
   report_timing -delay_type $delay -to [get_ports {sd_cmd sd_dat[*]}] -max_paths 20 -path_type full_clock_expanded -file $out/${direction}_${delay}.rpt
  }
 }
}
report_drc -no_waivers -file $out/drc.rpt
set f [open $out/pad_registers.tsv w]
foreach c [get_cells -hier -filter {NAME =~ phy/* && IS_SEQUENTIAL == 1}] {
 if {[get_property IOB $c] eq "TRUE"} {puts $f "$c\t[get_property LOC $c]\t[get_property BEL $c]"}
}
close $f
write_checkpoint -force $out/routed.dcp
puts "SD_IO_PROBE_FINISHED: timing fixture only, not a board bitstream"
