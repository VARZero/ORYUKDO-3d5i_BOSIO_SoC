# 3_10_PZ_DDR/ddr3_test.xdc and 3_12_PZ_UART/uart.xdc in Puzhi's 1_FPGA.rar.
# DDR bank and oscillator use the DDR example's 1.35 V standard.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
create_clock -name board200 -period 5.000 [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL135} [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL135 [get_ports sys_clk_n]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports rst_n]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports error]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports uart_rx]
