set root [file normalize [file dirname [info script]]/../..]
set out [file normalize [lindex $argv 0]]
file mkdir $out
cd $out
create_project -in_memory -part xc7a200tfbg484-2
set_param general.maxThreads 4
read_verilog -sv $root/soc/bosio/or_bo_axi_pkg.sv
read_verilog -sv $root/soc/bosio/or_bo_axi_fabric.sv
synth_design -mode out_of_context -top or_bo_axi_fabric -generic MASTERS=5 -part xc7a200tfbg484-2
create_clock -name fabric -period 10 [get_ports clk]
set_clock_uncertainty 0.300 [get_clocks fabric]
set data_in [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != reset_n}]
set data_out [get_ports -filter {DIRECTION == OUT}]
set_input_delay -clock fabric 2 $data_in
set_output_delay -clock fabric 2 $data_out
set_false_path -from [get_ports reset_n]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file $out/utilization.rpt
report_timing_summary -file $out/timing.rpt
report_timing -max_paths 10 -file $out/critical.rpt
write_checkpoint -force $out/routed.dcp
puts "FABRIC_PROBE_FINISHED: 5-master internal interface, not full board timing"
