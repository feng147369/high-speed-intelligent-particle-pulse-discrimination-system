## v13 AD9694 onechannel constraints (XC7K325T-2FFG900).
## Active interfaces: AD9694/JESD204B, LMK04828, RGMII Ethernet.
## Bank0=1.8V, Bank14=1.8V, Bank15=1.8V, Bank16=3.3V,
## Bank17=1.8V, Bank18=1.8V. External comparator/HV/DAC pins removed.
## Existing ADC lane mapping, clock and Ethernet constraints are retained.
##
## IMPORTANT TODO:
##   A) JESD PCB Lane swap:
##        RX0 <- AB0
##        RX1 <- AB1
##        RX2 <- CD1
##        RX3 <- CD0
## 这本身不会造成 XDC/HDL 编译失败，但上板前要在 AD9694 C/D pair
## 的 JESD lane mapping 中补偿（0x05B2/0x05B3）。
##
## B) 新板 AD9694 SYNC 为单端 CMOS，不是原板差分 LVDS。
## 顶层需使用随本文件提供的 migration_v1 版本：
##        AD9694_SYNC1_P / AD9694_SYNC2_P = rx_sync
## N 端支路在 PCB 中 NC
## AD9694 配置还需将 0x0572[4] 置 1。
##
##
## ============================================================================


## ============================================================================
## 1. 全局配置
## Bank0 = 1.8V
## ============================================================================
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
# FPGA 配置 Flash 使用 Quad SPI x4
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

set_property BITSTREAM.CONFIG.CONFIGRATE 12 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]


## ============================================================================
## 2. 系统 100MHz 单端时钟
## CLK_100M -> H14 / Bank18 / IO_L11P_T1_SRCC_18
## ============================================================================
# ============================================================================
# 系统100MHz主时钟
# ============================================================================

set_property PACKAGE_PIN H14 [get_ports SYS_CLK_P]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_CLK_P]

create_clock -period 10.000 -name SYS_CLK_P -waveform {0.000 5.000} [get_ports SYS_CLK_P]

set_input_jitter [get_clocks SYS_CLK_P] 0.100

## Clock Wizard 自带 clk_wiz_0.xdc 必须在工程中禁用。
## 其 create_clock / input_jitter 已由顶层 SYS_CLK_P 约束接管。
## 保留原 IP XDC 中的 PHASESHIFT_MODE 属性：
set_property PHASESHIFT_MODE WAVEFORM [get_cells clk_wiz_0_inst/inst/mmcm_adv_inst]

## ============================================================================
## 3. RGMII 千兆 PHY
## Bank15 = 1.8V
## ============================================================================
set_property PACKAGE_PIN L30 [get_ports PHY_TX_CLK]
set_property PACKAGE_PIN K30 [get_ports PHY_TX_CTRL]
set_property PACKAGE_PIN K29 [get_ports {PHY_TXD[0]}]
set_property PACKAGE_PIN J29 [get_ports {PHY_TXD[1]}]
set_property PACKAGE_PIN H29 [get_ports {PHY_TXD[2]}]
set_property PACKAGE_PIN J28 [get_ports {PHY_TXD[3]}]

set_property PACKAGE_PIN K28 [get_ports PHY_RX_CLK]
set_property PACKAGE_PIN N29 [get_ports PHY_RX_CTRL]
set_property PACKAGE_PIN N30 [get_ports {PHY_RXD[0]}]
set_property PACKAGE_PIN M29 [get_ports {PHY_RXD[1]}]
set_property PACKAGE_PIN M30 [get_ports {PHY_RXD[2]}]
set_property PACKAGE_PIN L28 [get_ports {PHY_RXD[3]}]

set_property PACKAGE_PIN K25 [get_ports PHY_RSTn]

set_property IOSTANDARD LVCMOS18 [get_ports PHY_TX_CLK]
set_property IOSTANDARD LVCMOS18 [get_ports PHY_TX_CTRL]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_TXD[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_TXD[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_TXD[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_TXD[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports PHY_RX_CLK]
set_property IOSTANDARD LVCMOS18 [get_ports PHY_RX_CTRL]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_RXD[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_RXD[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_RXD[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {PHY_RXD[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports PHY_RSTn]

## RGMII 时钟与时序：成熟千兆 demo 原样保留
create_clock -period 8.000 -name PHY_RX_CLK -waveform {0.000 4.000} [get_ports PHY_RX_CLK]

set_false_path -from [get_pins GMII_1000M_reg/C]

set_input_delay -clock [get_clocks PHY_RX_CLK] -max 3.000 [get_ports {PHY_RX_CTRL {PHY_RXD[*]}}]
set_input_delay -clock [get_clocks PHY_RX_CLK] -min 1.000 [get_ports {PHY_RX_CTRL {PHY_RXD[*]}}]

set_max_delay -datapath_only -from [get_clocks -quiet clk_out1_clk_wiz_0] -to [get_ports {PHY_TXD[*]}] 4.000
set_max_delay -datapath_only -from [get_clocks -quiet clk_out1_clk_wiz_0] -to [get_ports PHY_TX_CTRL] 4.000
set_max_delay -datapath_only -from [get_clocks -quiet clk_out2_clk_wiz_0] -to [get_ports PHY_TX_CLK] 4.000

set_max_delay -datapath_only -from [get_clocks -quiet clk_out4_clk_wiz_0] -to [get_ports PHY_RSTn] 10.000
set_min_delay -from [get_clocks -quiet clk_out4_clk_wiz_0] -to [get_ports PHY_RSTn] 0.000

##set_property -dict {PACKAGE_PIN J26 IOSTANDARD LVCMOS18} [get_ports PHY_MDC]
##set_property -dict {PACKAGE_PIN J27 IOSTANDARD LVCMOS18} [get_ports PHY_MDIO]

## ============================================================================
## 4. AD9694 / JESD204B
## ============================================================================

## 4.1 JESD204B Core Clock
## FPGA_JESD_CLK_P/N -> G13/F13, Bank18, MRCC pair
set_property -dict {PACKAGE_PIN G13 DIFF_TERM 0 IOSTANDARD LVDS_25} [get_ports jesd_clk_p]
set_property -dict {PACKAGE_PIN F13 DIFF_TERM 0 IOSTANDARD LVDS_25} [get_ports jesd_clk_n]
create_clock -period 4.000 -name jesd_sys_clk [get_ports jesd_clk_p]

## 4.2 JESD204B SYSREF
## FPGA_SYSREF_CLK_P/N -> D12/D13, Bank18, MRCC pair
set_property -dict {PACKAGE_PIN D12 DIFF_TERM 0 IOSTANDARD LVDS_25} [get_ports jesd_sysref_p]
set_property -dict {PACKAGE_PIN D13 DIFF_TERM 0 IOSTANDARD LVDS_25} [get_ports jesd_sysref_n]

## 4.3 GT reference clock + receive lanes
## 全部位于 GT Bank118
## GTX1_CLK_P/N -> MGTREFCLK0P/N_118 = C8/C7
##
## PCB lane:
##   RX0 = SERDESOUT_AB0
##   RX1 = SERDESOUT_AB1
## RX2 = SERDESOUT_CD1  <-- 与 CD0 交换
## RX3 = SERDESOUT_CD0  <-- 与 CD1 交换
##
## 保持成熟工程写法：只 LOC P 端，N 端由专用 GT 差分资源成对确定。
set_property PACKAGE_PIN C8 [get_ports GTH_REFCLK_P]
set_property PACKAGE_PIN E4 [get_ports {GTH_RXP[0]}]
set_property PACKAGE_PIN D6 [get_ports {GTH_RXP[1]}]
set_property PACKAGE_PIN B6 [get_ports {GTH_RXP[2]}]
set_property PACKAGE_PIN A8 [get_ports {GTH_RXP[3]}]

## 4.4 AD9694 SYNC
## Bank17 = 1.8V；SYNC 改为单端 1.8V CMOS。
## PCB 只驱动 SYNCINB+AB / SYNCINB+CD；N 支路按新版原理图 DNP/NC。
## 顶层删除 AD9694_SYNC1_N / AD9694_SYNC2_N，并移除 OBUFDS。
##
## AB: SYNC_JESD_AB_P -> B18
## CD: SYNC_JESD_CD_P -> C19
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS18} [get_ports AD9694_SYNC1_P]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18} [get_ports AD9694_SYNC2_P]


## ============================================================================
## 5. SPI 配置接口
## ============================================================================

## 5.1 LMK04828 / Bank16 = 3.3V
set_property -dict {PACKAGE_PIN A27 IOSTANDARD LVCMOS33} [get_ports LMK04828_SPI_RESET]
set_property -dict {PACKAGE_PIN A26 IOSTANDARD LVCMOS33} [get_ports LMK04828_SYNC]
set_property -dict {PACKAGE_PIN C24 IOSTANDARD LVCMOS33} [get_ports LMK04828_SPI_CS]
set_property -dict {PACKAGE_PIN B24 IOSTANDARD LVCMOS33} [get_ports LMK04828_SPI_CLK]
set_property -dict {PACKAGE_PIN A23 IOSTANDARD LVCMOS33} [get_ports LMK04828_SPI_SDIO]
set_property -dict {PACKAGE_PIN B23 IOSTANDARD LVCMOS33} [get_ports LMK04828_LD1]
set_property -dict {PACKAGE_PIN B28 IOSTANDARD LVCMOS33} [get_ports LMK04828_LD2]

## 5.2 AD9694 SPI / Bank17 = 1.8V
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS18} [get_ports AD9694_SPI_SCLK]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS18} [get_ports AD9694_SPI_SDIO]
set_property -dict {PACKAGE_PIN A22 IOSTANDARD LVCMOS18} [get_ports AD9694_SPI_CS]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS18} [get_ports AD9694_SPI_PDWN]


## 7. 异步时钟域关系
##
## SYS_CLK_P 为板级 100MHz primary clock。
## Vivado 会从 MMCM 自动派生 clk_out* generated clocks。
## -include_generated_clocks 将 SYS_CLK_P 及其所有派生时钟归为同一组。
## PHY_RX_CLK 与 JESD 250MHz 时钟分别来自独立外部时钟源，因此互相异步。
## ============================================================================
set_clock_groups -name ASYNC_SYS_PHY_JESD -asynchronous -group [get_clocks -include_generated_clocks SYS_CLK_P] -group [get_clocks PHY_RX_CLK] -group [get_clocks jesd_sys_clk]


## ============================================================================
## 8. SiTCP 跨时钟域约束（成熟千兆 demo 原样保留）
## ============================================================================
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXBUF/cmpWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXBUF/smpWrStatusAddr*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/orRdAct*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/irRdAct*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/muxEndTgl/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpMuxTrnsEnd*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX10Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/irMacFlowEnb/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX12Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX13Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX14Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX15Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX16Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX17Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX18Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX19Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX1AData*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX1BData*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/dlyBank0LastWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpBank0LastWrAddr*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/dlyBank1LastWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpBank1LastWrAddr*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/memRdReq*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/irMemRdReq*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXCNT/orMacTim*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXCNT/irMacPauseTime*/D}] 3.500
set_max_delay -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXCNT/orMacPause/C}] -to [get_pins -hier -filter {name =~ */GMII_TXCNT/irMacPauseExe_0/D}] 3.500
set_false_path -from [get_pins -hier -filter {name =~ */SiTCP_INT/SiTCP_RESET_OUT/C}]


# Debug Hub 使用板载、自由运行的 100 MHz 时钟

## ============================================================================
## End
## ============================================================================

set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets IB_100M]
