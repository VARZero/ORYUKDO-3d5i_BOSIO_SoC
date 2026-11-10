# KFB schematic J5 / BANK16. Native SD at 3.3V, no 1.8V switching.
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports sd_dclk]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports sd_cmd]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {sd_dat[0]}]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {sd_dat[1]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {sd_dat[2]}]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports {sd_dat[3]}]
# Fastest operating mode: 100 MHz fabric / 4. Initialization is slower.
# Preliminary board budget: <=14ns card output delay + 2ns PCB/skew.
# Must be verified against post-route I/O paths and actual card/board waveforms.
create_generated_clock -name sd_native_clk -source [get_pins ddr/ui_clk] -divide_by 4 [get_ports sd_dclk]
set_input_delay -clock sd_native_clk -clock_fall -max 16.0 [get_ports {sd_cmd sd_dat[*]}]
set_input_delay -clock sd_native_clk -clock_fall -min 0.0 [get_ports {sd_cmd sd_dat[*]}]
set_output_delay -clock sd_native_clk -max 5.0 [get_ports {sd_cmd sd_dat[*]}]
set_output_delay -clock sd_native_clk -min -5.0 [get_ports {sd_cmd sd_dat[*]}]
# Fast mode has four 100MHz cycles per SD period. Input pad registers sample
# at SD rise + 10ns, allowing for forwarded-clock pad delay and the return path.
# Setup end=3: card fall 20ns -> enabled capture 50ns. Hold end=3:
# next card fall 60ns -> that same capture 50ns (requirement -10ns).
set_multicycle_path -setup 3 -end -from [get_ports {sd_cmd sd_dat[*]}]
set_multicycle_path -hold 3 -end -from [get_ports {sd_cmd sd_dat[*]}]
# Host data AND output-enable registers change only at SD fall. Relative to the
# next SD rise, the source is the fabric edge 20ns earlier (setup start=2).
# Relative to the previous SD rise, the earliest change is 20ns later:
# hold start=3 compensates setup's -10ns shift and advances launch by 30ns.
# These exceptions encode verified clock-enable phases, not relaxed frequency.
set_multicycle_path -setup 2 -start -to [get_ports {sd_cmd sd_dat[*]}]
set_multicycle_path -hold 3 -start -to [get_ports {sd_cmd sd_dat[*]}]
