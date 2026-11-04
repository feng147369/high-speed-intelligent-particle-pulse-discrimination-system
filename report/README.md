# 设计报告与成果材料

作品名称：基于 FPGA 与轻量神经网络的高速氚水在线测量系统。

## 设计报告

[design_report.pdf](design_report.pdf) 包含作品需求、系统组成、硬件电路、FPGA 与上位机、功能验证以及氚水测量成果。公开报告保留探测功能、外部连接与整机外观介绍。

报告包含高速采集、双样点流水、预筛与特征、定点 CNN、同事件门控、缓存、能谱、完整包调度、上位机和实测结果。

## 框图

- [系统框图](figures/system.png)
- [事件处理流程](figures/event_flow.png)
- [上位机流程](figures/host_flow.png)

整机、板卡、散热及测量平台实物见 `../board/photos/`。

## 成果对应

| 成果 | 位置 |
|---|---|
| 顶层与子模块 | ../src/ |
| 功能验证 | ../sim/ |
| 成功运行文本报告 | ../build/ |
| 板卡与测量平台 | ../board/photos/ |
| 测量与模型数据 | ../data/ |

## 测量成果

本底计数率 0.36 cps，标准样品计数率 160.24 cps，净计数率 159.88 cps，探测效率约 0.04%。4 h 探测限为 3255 Bq/L，12 h 连续测量计数率 RSD 为 0.96%。

当前完整 v14 的工程参数与最终运行结果见根目录 README.md 及 build/reports/，包括 1281 点原始缓存、257 点 CNN、满码否决、时间戳、双流传输和四页上位机对应的 FPGA 实现。

技能入口见 `../skill/README.md`；协作记录见 [llm_collaboration.md](llm_collaboration.md)。
