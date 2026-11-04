`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ngamma_ttt_discriminator_v1_timingfix1
//
// 目的：保持 Tail-to-Total 特征提取结构，并支持CMD27/CMD28运行时动态配置，
//       将事件特征提取数据通路拆成两级流水，降低 250 MHz 下组合路径深度。
//
// 关键改动：
//   1) 触发检测改为等价的 17bit 阈值比较：data > baseline + threshold。
//   2) 触发样点先寄存净幅度，在 S_START 中初始化事件累加器。
//   3) 事件样点流水：
//        E1: 扣基线 -> amp0/amp1 寄存 
//        E2: max/sum/width -> 寄存
//        ACC: 峰值比较、积分累加、窗口结束判断
// 
//   5) 为便于 A/B 对比，暂时保留原 ila_feature。
//////////////////////////////////////////////////////////////////////////////////

module ngamma_ttt_discriminator_v1 #(
    parameter EVENT_CONTROL = 0,
    parameter DATA_W          = 16,
    parameter SUM_W           = 32,
    parameter DEFAULT_TOTAL_GATE_CYC      = 16'd256,
    parameter DEFAULT_PSD_THRESHOLD_X100 = 16'd70,
    parameter TAIL_START_CYC  = 16'd20,
    parameter DEAD_CYCLES     = 32'd200
)(
    input wire i_external_mode, i_event_start,
    input                       glblclk,  // 处理时钟
    input                       i_rst_n,  // 低有效复位

    input      [DATA_W-1:0]     i_data0,  // 前相数据
    input      [DATA_W-1:0]     i_data1,  // 后相数据
    input                       i_data_valid,  // 数据有效

    input                       i_enable,  // 使能信号
    input      [DATA_W-1:0]     i_baseline,  // 基线输入
    input                       i_baseline_valid,  // 基线有效
    input      [DATA_W-1:0]     i_threshold,  // 判别阈值

    // CMD27/CMD28 已经由CDC送到glblclk域的保持型配置
    input      [15:0]           i_total_gate_cycles,  // 总积分门宽
    input      [15:0]           i_psd_threshold_x100,  // 判别阈值

    output reg [DATA_W-1:0]     o_base_latch,  // 基线值
    output reg [DATA_W-1:0]     o_peak,  // 脉冲峰值
    output reg [15:0]           o_peak_time,  // 峰值时刻
    output reg [15:0]           o_width_samples,  // 脉冲宽度
    output reg [SUM_W-1:0]      o_q_total,  // 总积分
    output reg [SUM_W-1:0]      o_q_tail,  // 尾积分
    output reg                  o_feature_valid,  // 特征数据有效
    output     [3:0]            o_state_dbg,  // 状态值

    output reg                  o_class_valid,  // 分类结果有效
    output reg                  o_particle_type,  // 粒子类型
    output reg [DATA_W-1:0]     o_class_peak  // 分类峰值
);

//==============================================================================
// 1. 状态机
//==============================================================================
localparam [3:0]
    S_IDLE    = 4'd0,
    S_START   = 4'd1,
    S_CAPTURE = 4'd2,
    S_DRAIN   = 4'd3,
    S_DEAD    = 4'd4;

reg [3:0] state;
assign o_state_dbg = state;

//==============================================================================
// 2. 事件内部寄存器
//==============================================================================
reg [DATA_W-1:0] base_latch;
reg [DATA_W-1:0] peak_cur;
reg [15:0]       peak_time_cur;
reg [15:0]       width_cnt;
reg [15:0]       gate_cnt;       // 下一对输入样点的事件索引
reg [SUM_W-1:0]  q_total_acc;
reg [SUM_W-1:0]  q_tail_acc;
reg [31:0]       dead_cnt;

// 每个事件开始时锁存CMD27/CMD28配置，防止事件进行中参数改变。
reg [15:0]       event_total_gate_cyc;
reg [6:0]        event_psd_threshold_x100;

// 触发样点净幅度寄存器
reg [DATA_W-1:0] trig_amp0_r;
reg [DATA_W-1:0] trig_amp1_r;
reg [DATA_W-1:0] trig_threshold_r;

//==============================================================================
// 3. IDLE 触发检测
//
// 原逻辑：max(max(data0-baseline,0), max(data1-baseline,0)) > threshold
// 等价为：data0 > baseline+threshold 或 data1 > baseline+threshold
// 用 17bit 扩展避免 baseline+threshold 溢出。
//==============================================================================
wire [DATA_W:0] trig_level_ext =
    {1'b0, i_baseline} + {1'b0, i_threshold};

wire traditional_start =
    i_enable &&
    i_baseline_valid &&
    i_data_valid &&
    (({1'b0, i_data0} > trig_level_ext) ||
     ({1'b0, i_data1} > trig_level_ext));

wire trig_start_fast = (EVENT_CONTROL && i_external_mode) ? i_event_start : traditional_start;
wire [DATA_W-1:0] amp0_idle =
    (i_data0 > i_baseline) ? (i_data0 - i_baseline) : {DATA_W{1'b0}};

wire [DATA_W-1:0] amp1_idle =
    (i_data1 > i_baseline) ? (i_data1 - i_baseline) : {DATA_W{1'b0}};

wire [DATA_W-1:0] trig_pair_max =
    (trig_amp0_r > trig_amp1_r) ? trig_amp0_r : trig_amp1_r;

wire [SUM_W-1:0] trig_pair_sum =
    {{(SUM_W-DATA_W){1'b0}}, trig_amp0_r} +
    {{(SUM_W-DATA_W){1'b0}}, trig_amp1_r};

wire [1:0] trig_width_inc =
    (trig_amp0_r > trig_threshold_r ? 2'd1 : 2'd0) +
    (trig_amp1_r > trig_threshold_r ? 2'd1 : 2'd0);

//==============================================================================
// 4. 事件数据流水
//
// E1：扣基线
// E2：max / sum / width
//==============================================================================
reg                    e1_valid;
reg [DATA_W-1:0]       e1_amp0;
reg [DATA_W-1:0]       e1_amp1;
reg [DATA_W-1:0]       e1_threshold;
reg [15:0]             e1_idx;

reg                    e2_valid;
reg [DATA_W-1:0]       e2_pair_max;
reg [SUM_W-1:0]        e2_pair_sum;
reg [1:0]              e2_width_inc;
reg [15:0]             e2_idx;

wire accept_evt_input =
    ((state == S_START) || (state == S_CAPTURE)) && i_data_valid;

wire [DATA_W-1:0] evt_amp0_comb =
    (i_data0 > base_latch) ? (i_data0 - base_latch) : {DATA_W{1'b0}};

wire [DATA_W-1:0] evt_amp1_comb =
    (i_data1 > base_latch) ? (i_data1 - base_latch) : {DATA_W{1'b0}};

// E1: 只做扣基线并寄存
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        e1_valid     <= 1'b0;
        e1_amp0      <= {DATA_W{1'b0}};
        e1_amp1      <= {DATA_W{1'b0}};
        e1_threshold <= {DATA_W{1'b0}};
        e1_idx       <= 16'd0;
    end else begin
        e1_valid <= accept_evt_input;

        if (accept_evt_input) begin
            e1_amp0      <= evt_amp0_comb;
            e1_amp1      <= evt_amp1_comb;
            e1_threshold <= i_threshold;
            e1_idx       <= gate_cnt;
        end
    end
end

// E2: 从 E1 寄存器出发做 max/sum/width，再寄存
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        e2_valid     <= 1'b0;
        e2_pair_max  <= {DATA_W{1'b0}};
        e2_pair_sum  <= {SUM_W{1'b0}};
        e2_width_inc <= 2'd0;
        e2_idx       <= 16'd0;
    end else begin
        e2_valid <= e1_valid;

        if (e1_valid) begin
            e2_pair_max <= (e1_amp0 > e1_amp1) ? e1_amp0 : e1_amp1;

            e2_pair_sum <=
                {{(SUM_W-DATA_W){1'b0}}, e1_amp0} +
                {{(SUM_W-DATA_W){1'b0}}, e1_amp1};

            e2_width_inc <=
                (e1_amp0 > e1_threshold ? 2'd1 : 2'd0) +
                (e1_amp1 > e1_threshold ? 2'd1 : 2'd0);

            e2_idx <= e1_idx;
        end
    end
end

//==============================================================================
// 5. 主状态机与特征累加
//==============================================================================
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        state           <= S_IDLE;
        base_latch      <= 16'h8000;
        peak_cur        <= {DATA_W{1'b0}};
        peak_time_cur   <= 16'd0;
        width_cnt       <= 16'd0;
        gate_cnt        <= 16'd0;
        q_total_acc     <= {SUM_W{1'b0}};
        q_tail_acc      <= {SUM_W{1'b0}};
        dead_cnt        <= 32'd0;

        event_total_gate_cyc       <= DEFAULT_TOTAL_GATE_CYC;
        event_psd_threshold_x100   <= DEFAULT_PSD_THRESHOLD_X100[6:0];

        trig_amp0_r     <= {DATA_W{1'b0}};
        trig_amp1_r     <= {DATA_W{1'b0}};
        trig_threshold_r<= {DATA_W{1'b0}};

        o_base_latch    <= 16'h8000;
        o_peak          <= {DATA_W{1'b0}};
        o_peak_time     <= 16'd0;
        o_width_samples <= 16'd0;
        o_q_total       <= {SUM_W{1'b0}};
        o_q_tail        <= {SUM_W{1'b0}};
        o_feature_valid <= 1'b0;
    end else begin
        o_feature_valid <= 1'b0;

        case (state)

            //------------------------------------------------------------------
            // 等待触发：只锁存触发样点的净幅度和基线
            //------------------------------------------------------------------
            S_IDLE: begin
                if (trig_start_fast) begin
                    base_latch       <= i_baseline;
                    trig_amp0_r      <= amp0_idle;
                    trig_amp1_r      <= amp1_idle;
                    trig_threshold_r <= i_threshold;

                    // 防御性范围检查：正常情况下parser已经保证合法。
                    if ((i_total_gate_cycles >= 16'd1) &&
                        (i_total_gate_cycles <= 16'h7FFF))
                        event_total_gate_cyc <= i_total_gate_cycles;
                    else
                        event_total_gate_cyc <= DEFAULT_TOTAL_GATE_CYC;

                    if ((i_psd_threshold_x100 >= 16'd1) &&
                        (i_psd_threshold_x100 <= 16'd99))
                        event_psd_threshold_x100 <= i_psd_threshold_x100[6:0];
                    else
                        event_psd_threshold_x100 <= DEFAULT_PSD_THRESHOLD_X100[6:0];

                    gate_cnt         <= 16'd1;
                    state            <= S_START;
                end
            end

            //------------------------------------------------------------------
            // 用已经寄存的触发样点初始化事件；
            // 同一拍 E1 可以接收触发后的第 1 对样点。
            //------------------------------------------------------------------
            S_START: begin
                peak_cur       <= trig_pair_max;
                peak_time_cur  <= 16'd0;
                width_cnt      <= {14'd0, trig_width_inc};
                q_total_acc    <= trig_pair_sum;

                if (TAIL_START_CYC == 16'd0)
                    q_tail_acc <= trig_pair_sum;
                else
                    q_tail_acc <= {SUM_W{1'b0}};

                if (event_total_gate_cyc <= 16'd1) begin
                    o_base_latch    <= base_latch;
                    o_peak          <= trig_pair_max;
                    o_peak_time     <= 16'd0;
                    o_width_samples <= {14'd0, trig_width_inc};
                    o_q_total       <= trig_pair_sum;
                    o_q_tail        <= (TAIL_START_CYC == 16'd0) ? trig_pair_sum : {SUM_W{1'b0}};
                    o_feature_valid <= 1'b1;
                    dead_cnt        <= DEAD_CYCLES;
                    state           <= S_DEAD;
                end else if (i_data_valid) begin
                    // 这一拍 E1 已经接收 gate_cnt 对应的数据
                    if (gate_cnt >= (event_total_gate_cyc - 1'b1)) begin
                        state <= S_DRAIN;
                    end else begin
                        gate_cnt <= gate_cnt + 1'b1;
                        state    <= S_CAPTURE;
                    end
                end
            end

            //------------------------------------------------------------------
            // 连续接收剩余样点，同时消费 E2 流水结果
            //------------------------------------------------------------------
            S_CAPTURE: begin
                if (e2_valid) begin
                    // 峰值与峰位置
                    if (e2_pair_max > peak_cur) begin
                        peak_cur      <= e2_pair_max;
                        peak_time_cur <= e2_idx;
                    end

                    width_cnt   <= width_cnt + {14'd0, e2_width_inc};
                    q_total_acc <= q_total_acc + e2_pair_sum;

                    if (e2_idx >= TAIL_START_CYC)
                        q_tail_acc <= q_tail_acc + e2_pair_sum;
                end

                if (i_data_valid) begin
                    // 这一拍 E1 已经接收 gate_cnt 对应的数据
                    if (gate_cnt >= (event_total_gate_cyc - 1'b1)) begin
                        state <= S_DRAIN;
                    end else begin
                        gate_cnt <= gate_cnt + 1'b1;
                    end
                end
            end

            //------------------------------------------------------------------
            // 输入窗口已经收完，等待最后的 E1/E2 流水结果到达
            //------------------------------------------------------------------
            S_DRAIN: begin
                if (e2_valid) begin
                    if (e2_idx >= (event_total_gate_cyc - 1'b1)) begin
                        // 最后一对样点：直接形成最终输出，避免漏加最后一拍
                        o_base_latch <= base_latch;

                        if (e2_pair_max > peak_cur) begin
                            o_peak      <= e2_pair_max;
                            o_peak_time <= e2_idx;
                        end else begin
                            o_peak      <= peak_cur;
                            o_peak_time <= peak_time_cur;
                        end

                        o_width_samples <= width_cnt + {14'd0, e2_width_inc};
                        o_q_total       <= q_total_acc + e2_pair_sum;

                        if (e2_idx >= TAIL_START_CYC)
                            o_q_tail <= q_tail_acc + e2_pair_sum;
                        else
                            o_q_tail <= q_tail_acc;

                        o_feature_valid <= 1'b1;
                        dead_cnt        <= DEAD_CYCLES;
                        state           <= S_DEAD;
                    end else begin
                        // 正常消费流水中的中间样点
                        if (e2_pair_max > peak_cur) begin
                            peak_cur      <= e2_pair_max;
                            peak_time_cur <= e2_idx;
                        end

                        width_cnt   <= width_cnt + {14'd0, e2_width_inc};
                        q_total_acc <= q_total_acc + e2_pair_sum;

                        if (e2_idx >= TAIL_START_CYC)
                            q_tail_acc <= q_tail_acc + e2_pair_sum;
                    end
                end
            end

            //------------------------------------------------------------------
            // 死区
            //------------------------------------------------------------------
            S_DEAD: begin
                if (dead_cnt != 32'd0)
                    dead_cnt <= dead_cnt - 1'b1;
                else
                    state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

//==============================================================================
// 6. 动态PSD分类器 -- 250MHz DSP48E1 timing closure 版
//
// 实测最差路径：
//   o_q_total_reg[*] -> total_x_thr_r0__0/DSP48E1/PCIN[*]
//
// 根因是旧写法把32bit Qtotal和7bit阈值都先扩展成39bit，再写：
//   qtotal_ext * threshold_ext
// Vivado因此推导成宽动态乘法并形成DSP48E1级联路径。
//
// 本版只针对该根因修改：
//   Qtotal[15:0]  * T  -> 1个16x7乘法
//   Qtotal[31:16] * T  -> 1个16x7乘法
//   下一拍再组合：low + (high << 16)
//
// 两个16x7乘法都能独立映射到DSP48E1，不需要39x39级联。
// 乘法级寄存器使用同步复位，便于Vivado吸收到DSP48E1内部流水寄存器。
// AMD/Xilinx建议DSP算术充分流水化以获得高频时序。
//
// PSD = Qtail / Qtotal
// CMD28发送 T = threshold*100，范围1..99。
//
//   Qtail * 100 >= Qtotal * T -> Gamma   (particle_type=0)
//   Qtail * 100 <  Qtotal * T -> Neutron (particle_type=1)
//
// 当前工程 SUM_W=32；下面写法保留参数化，但要求 SUM_W >= 17。
//==============================================================================

localparam integer CLASS_MUL_W = SUM_W + 7;
localparam integer CLASS_PAD   = CLASS_MUL_W - SUM_W;

localparam integer TOTAL_LO_W  = 16;
localparam integer TOTAL_HI_W  = SUM_W - TOTAL_LO_W;
localparam integer LO_MUL_W    = TOTAL_LO_W + 7;
localparam integer HI_MUL_W    = TOTAL_HI_W + 7;

wire [6:0] psd_thr7 = event_psd_threshold_x100;

wire [CLASS_MUL_W-1:0] qtail_ext =
    {{CLASS_PAD{1'b0}}, o_q_tail};

// -----------------------------------------------------------------------------
// Stage 0：两个独立小乘法 + Qtail*100的第一层
// -----------------------------------------------------------------------------
(* use_dsp = "yes" *) reg [LO_MUL_W-1:0] total_lo_mul_r;
(* use_dsp = "yes" *) reg [HI_MUL_W-1:0] total_hi_mul_r;

reg [CLASS_MUL_W-1:0] tail_x96_r;
reg [CLASS_MUL_W-1:0] tail_x4_r;

reg [DATA_W-1:0] class_peak_s0;
reg              class_valid_s0;

// 注意：这里故意采用同步复位，避免异步复位妨碍乘法流水寄存器进入DSP48E1。
always @(posedge glblclk) begin
    if (!i_rst_n) begin
        total_lo_mul_r <= {LO_MUL_W{1'b0}};
        total_hi_mul_r <= {HI_MUL_W{1'b0}};
        tail_x96_r     <= {CLASS_MUL_W{1'b0}};
        tail_x4_r      <= {CLASS_MUL_W{1'b0}};
        class_peak_s0  <= {DATA_W{1'b0}};
        class_valid_s0 <= 1'b0;
    end
    else begin
        class_valid_s0 <= o_feature_valid;

        if (o_feature_valid) begin
            // 两个乘法都只有16x7（SUM_W=32时），避免DSP48E1宽乘法级联。
            total_lo_mul_r <= o_q_total[TOTAL_LO_W-1:0] * psd_thr7;
            total_hi_mul_r <= o_q_total[SUM_W-1:TOTAL_LO_W] * psd_thr7;

            // 100 = 96 + 4 = 64 + 32 + 4
            // 第一层只做一次39bit加法。
            tail_x96_r <= (qtail_ext << 6) + (qtail_ext << 5);
            tail_x4_r  <= (qtail_ext << 2);

            class_peak_s0 <= o_peak;
        end
    end
end

// -----------------------------------------------------------------------------
// Stage 1：组合两个部分积，同时完成Qtail*100
// -----------------------------------------------------------------------------
wire [CLASS_MUL_W-1:0] total_lo_ext =
    {{(CLASS_MUL_W-LO_MUL_W){1'b0}}, total_lo_mul_r};

wire [CLASS_MUL_W-1:0] total_hi_ext =
    {{(CLASS_MUL_W-HI_MUL_W){1'b0}}, total_hi_mul_r};

reg [CLASS_MUL_W-1:0] total_x_thr_r;
reg [CLASS_MUL_W-1:0] tail_x100_r;
reg [DATA_W-1:0]      class_peak_s1;
reg                   class_valid_s1;

always @(posedge glblclk) begin
    if (!i_rst_n) begin
        total_x_thr_r <= {CLASS_MUL_W{1'b0}};
        tail_x100_r   <= {CLASS_MUL_W{1'b0}};
        class_peak_s1 <= {DATA_W{1'b0}};
        class_valid_s1<= 1'b0;
    end
    else begin
        class_valid_s1 <= class_valid_s0;

        if (class_valid_s0) begin
            total_x_thr_r <= total_lo_ext + (total_hi_ext << TOTAL_LO_W);
            tail_x100_r   <= tail_x96_r + tail_x4_r;
            class_peak_s1 <= class_peak_s0;
        end
    end
end

// -----------------------------------------------------------------------------
// Stage 2：最终比较并输出
// -----------------------------------------------------------------------------
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_class_valid   <= 1'b0;
        o_particle_type <= 1'b0;
        o_class_peak    <= {DATA_W{1'b0}};
    end
    else begin
        o_class_valid <= class_valid_s1;

        if (class_valid_s1) begin
            if (tail_x100_r >= total_x_thr_r)
                o_particle_type <= 1'b0;  // Gamma
            else
                o_particle_type <= 1'b1;  // Neutron

            o_class_peak <= class_peak_s1;
        end
    end
end

//==============================================================================
// 7. ILA：第一轮 A/B 先保留，便于只观察 RTL 流水化的影响
//==============================================================================
//ila_feature ila_feature (
  //  .clk    (glblclk),
   // .probe0 (o_class_valid),
   // .probe1 (o_class_peak),
   // .probe2 (o_width_samples),
   // .probe3 (o_q_total),
  //  .probe4 (o_q_tail),
  //  .probe5 (o_peak_time),
  //  .probe6 (o_base_latch),
 //   .probe7 ({3'b000, o_particle_type})
//);

endmodule