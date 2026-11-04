# 器件规则与官方依据

以下是**案例指纹**，不是通用初始化表。每次使用前核对实物型号、修订版与 IP 版本。

## 关键寄存器与位语义

| 位置 | 案例含义 | 边界 |
|---|---|---|
| AD9694 Rev.C SPI 0x0004 | 只读 ID 寄存器，读回 DB | 不凭一次读取鉴定真伪 |
| AD6684 Rev.A SPI 0x0004 | 只读 ID 寄存器，读回 DC | 先验证 SPI 可信；AB/CD 为通道对 |
| AD9694 SPI 0x0200 | 00 = 全带宽；08 不在其支持模式表内 | 不套用 6684 的配置 |
| AD6684 SPI 0x0200 | 00 = 9 位全带宽路径；08 = VDR；复位默认 07 为 NSR | VDR 受输入频谱条件约束，不保证所有输入达到 14 位 ENOB |
| N / N′ | 传输格式与容器宽度 | 不证明有效信息位数 |
| AMD JESD v7.2 AXI 0x008 bit0 | ILAS 支持 | 不是调试 ILA 的开关 |
| AMD AXI 0x010 bit0 | 1 = 每次 SYSREF 重对齐；0 = 仅首次 | 不能取消启动所需的有效 SYSREF；重同步需另查 bit16 |
| AMD AXI 0x028 | lane 位掩码 01 / 0F | 单通道应用不自动决定 lane 数 |
| AD9694 SPI 0x0120 | SYSREF 捕获，N-shot 完成后自清除 | 不表示后续事件持续参与采样 |
| LMK 0x12F = 0x55 | 本例 ADC 侧输出 LVPECL 格式 5 | 不能只凭图纸上的 LVDS 注释 |
| LMK 0x107 = 0x11 | 本例 FPGA 侧输出 LVDS 格式 1 | 与 ADC 是不同输出、不同支路 |

## 拓扑禁忌

- **串联电容**隔直；**240 Ω 到地**是负载/电流回路；**P/N 之间 100 Ω** 是差分端接。三者不可互换。
- 外部端接已存在时，不盲开内部端接。
- 本例 R102/R103 附近属 ADC 支路；R93/R95/R185 属 FPGA 支路，D12/D13、DIFF_TERM=FALSE。编号只适用于本图。
- **对地下拉改 0 Ω 会短接输出**。不能把"串联电容换 0 Ω"的推断套到对地负载上。

### 资料冲突的处理方式

同一节点在不同记录中曾被称为"串联电容"，后经实物核对为"两颗 240 Ω 分别接 GND"。规则：**以实物拓扑为准**，冲突时保留待核状态并注明来源差异；在拓扑确认前不得据此给出拆改建议。

## 官方依据

- [AD9694 Rev.C](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9694.pdf)：第 74 页 ID；第 65–67 页 SYSREF；模式、传输格式及未公开地址/复位等待规则。
- [AD6684 Rev.A](https://www.analog.com/media/en/technical-documentation/data-sheets/ad6684.pdf)：第 75 页 ID；第 32 页全带宽输出位宽；第 51–52 页 VDR；第 80 页模式表。
- [AMD PG066 v7.2](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/jesd204/v7_2/pg066-jesd204.pdf)：表 2-17/2-19/2-25，SYSREF 第 62–63 页。
- [TI LMK04828 Rev.AS](https://www.ti.com/lit/ds/symlink/lmk04828.pdf)：表 25，10.4.1/图 29，LVPECL DCLKout/SDCLKout 负载 120–240 Ω。

**换版必须重新核对**：ID、SYSREF 相关位、模式表、负载条款，以及错误报告字段的位布局。负载范围符合不等于整个接口达标。
