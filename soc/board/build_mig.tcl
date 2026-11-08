set here [file normalize [file dirname [info script]]]
set out [file normalize [lindex $argv 0]]
file mkdir $out
create_project kfb_bosio_mig $out -part xc7a200tfbg484-2
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name mig_7series_0
set_property CONFIG.XML_INPUT_FILE $here/mig_a.prj [get_ips mig_7series_0]
generate_target all [get_ips mig_7series_0]
create_ip_run [get_ips mig_7series_0]
launch_runs mig_7series_0_synth_1 -jobs 2
wait_on_run mig_7series_0_synth_1
if {[get_property PROGRESS [get_runs mig_7series_0_synth_1]] ne "100%"} {error "MIG synthesis failed"}
puts "PASS KFB_BOSIO_MIG_IP"
close_project
