# 工程实现报告

## 固定版本

整机采用 Vivado 2022.1，器件为 xc7k325tffg900-2，顶层为 top_tcp_adc。AI 模块由 2026.1 工具环境生成，纯 RTL 与 ROM 集成到整机。

本目录保存以下一组成功运行的文本报告：

- 综合：synth_raw_recording_20261103
- 实现：impl_raw_recording_20261103

## 报告组织

- runs/synth_raw_recording_20261103/：成功综合运行的资源报告。
- runs/impl_raw_recording_20261103/：本次实现运行的时序、资源、布线、功耗与 DRC 文本报告。
- reports/：最终检查报告和验证汇总。

## 实现结果

| 项目 | 结果 |
|---|---|
| WNS / WHS | +0.069 ns / +0.052 ns |
| LUT | 40074，19.66% |
| 寄存器 | 55472，13.61% |
| Block RAM Tile / DSP | 265 / 318 |
| 总线偏斜约束 | 14 项，最小余量 +3.195 ns |
| 布线错误 / DRC Error / DRC Critical Warning | 0 / 0 / 0 |

## 构建流程

整机完成顶层与子模块集成、IP 配置、约束加载、CNN ROM 初始化、综合、布局布线及布线后物理优化。综合前置脚本复制 4 个 CNN 权重文件，使运行目录中的 ROM 与模型版本对应。

## 文件对应

`timing_routed.rpt`、`utilization.rpt`、`route_status.rpt`、`bus_skew.rpt`、`drc.rpt` 分别记录时序、资源、布线、总线偏斜和设计规则检查。当前汇总为 `verification_results.json`。

公开文件校验值见 `../manifest.json`。
