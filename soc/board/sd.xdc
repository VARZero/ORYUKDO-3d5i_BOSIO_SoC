# Puzhi 3_13_PZ_SD/sd.xdc. CS and MOSI idle high.
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_dclk]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_ncs]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_mosi]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports sd_miso]
# A minimum 80 ns half-cycle separates pin updates from receiver sampling.
# Bound each local pad path, including the incoming path to the first sampler.
set_max_delay -datapath_only 12 -from [get_cells -hier -filter {NAME =~ *boot* && IS_SEQUENTIAL == 1}] -to [get_ports {sd_dclk sd_ncs sd_mosi}]
set_max_delay -datapath_only 12 -from [get_ports sd_miso] -to [get_cells -hier -filter {NAME =~ *miso_sync_reg*}]
