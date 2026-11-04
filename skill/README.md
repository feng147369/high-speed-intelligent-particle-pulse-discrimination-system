# 高速 ADC 采集与脉冲 AI 技能包

本技能包来自高速氚水测量系统的开发与调试，包含 ADC/JESD204B 采集链排障，以及脉冲波形 CNN 训练、定点化和 FPGA 接入两条工作线。

技能包将开发过程中形成的数据分析方法、实验步骤、数值校验和问题定位经验整理为可复用流程，供同类高速采集与在线波形处理项目使用。

## 目录

```text
skill/
├── README.md
├── workflow.md
├── pitfalls.md
└── fpga-adc-pulse-ai/
    ├── SKILL.md
    ├── agents/
    ├── assets/
    ├── evidence/
    │   ├── adc/
    │   └── ai/
    ├── references/
    └── scripts/
```

## 技能一：ADC 原始码与采集链排障

### 适用场景

- ADC 原始采样字出现低位固定或码值间隔异常。
- 测试模式和正常采集结果不同。
- 同一板卡在示例工程与业务工程中的表现不同。
- JESD204B 同步状态、有效数据和能谱结果需要联合检查。
- SPI 回读、器件配置与输出数据格式需要交叉核对。

### 使用方法

1. 确定实际使用的板卡、顶层、源码、IP 和配置。
2. 从 ADC 解包后的原始码开始分析，记录进制、位宽、移位和有效条件。
3. 统计低位集合、相邻码值间隔、样点顺序及有效事件。
4. 检查 SPI 读写时序、SDIO 方向和回读校验。
5. 对照器件资料核对身份、工作模式和数据格式。
6. 比较示例工程与业务工程的实际配置。
7. 每次改变一个变量，保存修改前后的数据及结果。

### 项目中的应用

该流程用于分析原始采样字低位固定、能谱双峰、SPI 回读和 JESD204B 同步问题。

采样码分析将“位数异常”落实为低位集合与码值间隔统计；工程对照将 ADC、时钟、JESD204B 和运行期配置逐项关联，形成问题定位及复验记录。

### 使用条件

分析时明确原始数据格式、有效信号和实际工作模式。更换 ADC 型号、修订版、采样率或通道映射时，重新核对对应配置。

## 技能二：脉冲波形 CNN 的定点化与 FPGA 接入

### 适用场景

已有原始脉冲采集数据，需要训练轻量模型，并将软件模型部署到 FPGA 实时事件处理链。

### 使用方法

1. 定义观察窗的物理时间、采样间隔和点数。
2. 将人工波形判据转化为可执行标签规则。
3. 按采集时间组织训练、验证和留出数据。
4. 训练轻量 CNN，并用验证集选择工作阈值。
5. 固定预处理、权重、定点格式和舍入规则。
6. 建立整数参考，与 HLS C 和 RTL 逐分数比较。
7. 将输入、阈值、事件号和最终判决按事件关联。
8. 在真实顶层检查缓存、背压、复位、上传和能谱写入。

### 项目中的应用

当前模型使用 25755 条实测波形，原始帧为 1281 点、2 ns/点，经五点均值和步长 5 处理形成 257 点输入，输入点间隔为 10 ns。

网络采用三层一维卷积、池化、全局平均和全连接结构。权重为 12 位、8 位小数，激活为 24 位、14 位小数。默认得分阈值为 Q14 整数 4043。

128 条真实波形完成 HLS C 与 RTL 整数得分核对。24 帧完整 AI 支路测试覆盖原始满码、窗口边界、采样相位和真实留出波形。

### 使用条件

模型参数与采样格式、增益、触发条件及标签规则对应。改变输入条件时，按相同流程重新生成参考结果并评估工作阈值。

## 技能三：原始条件检查与事件级联合判决

### 适用场景

原始波形经过均值、抽取或其他预处理后，仍需保留原始域中的确定性判据。

### 使用方法

1. 明确需要在原始域判断的条件。
2. 在信息变换前计算对应标志。
3. 将标志与事件号、输入帧和模型结果关联。
4. 保存模型得分与组合判决原因。
5. 在最终门控处统一控制上传和统计。

### 项目中的应用

完整 1281 点原始帧在均值处理前检查满码。任一点达到 65532 或以上时置满码标志，AI 判决由 CNN 得分和原始满码条件联合形成，再与预筛结果共同决定事件放行。

在 3864 条时间留出波形上，按已定义的波形规则标签统计，联合判决的正类召回率为 84.15%，负类误放率为 0.37%，通过事件中符合规则的比例为 98.99%。

## 可复用脚本

脚本位于 fpga-adc-pulse-ai/scripts/，使用 Python 标准库。

```text
python scripts/analyze_ila_csv.py capture.csv
python scripts/analyze_ila_csv.py capture.csv --sample-rate 500000000 --pulse-threshold 2500 --output analysis.json
python scripts/ila_audit.py capture.csv --signal "cha_sample0_t[15:0]" --bits 14 --shift 2 --valid rx_tvalid --out audit.json
python scripts/ila_audit.py capture.csv --signal "ng_class_peak[15:0]" --bits 16 --event ng_class_valid --out events.json
```

以上命令在 fpga-adc-pulse-ai/ 内执行，探针名按实际 CSV 列名填写。

脚本支持低位活动、有效周期、事件计数、双样点交织、进制解析和 JSON 结果输出。

## 文件入口

| 文件或目录 | 内容 |
|---|---|
| workflow.md | 项目工作流与复用提示词 |
| pitfalls.md | 问题、定位方法及处理经验 |
| fpga-adc-pulse-ai/SKILL.md | 技能执行入口 |
| references/01-evidence-gates.md | ADC 排障步骤及判据 |
| references/02-device-rules.md | 器件与配置核对 |
| references/04-experiment-contracts.md | 实验记录与操作约定 |
| references/05-ai-case-parameters.md | 模型、预处理和定点参数 |
| references/06-verification.md | 验证组织与测试项目 |
| references/07-collaboration-and-workflow.md | 协作记录与工作流 |
| references/08-skill-distillation.md | 技能提炼过程 |
| evidence/ | ADC 与 AI 结果摘要 |
| assets/ | SPI 只读诊断参考 RTL 和测试平台 |

表中 references/、evidence/、assets/ 均位于 fpga-adc-pulse-ai/ 内。
