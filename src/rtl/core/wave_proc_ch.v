`timescale 1ns / 1ps

module wave_proc_ch #(
    parameter MAX_UPCOUNT   = 3'd2,
    parameter MAX_FP_WIN    = 14'd64,
    parameter MAX_DEADTIME  = 8'd4,
    parameter MAX_DEADTIME2 = 8'd2,
    parameter MAX_ESCAPE    = 16'd10240,
    parameter WAIT_CYCLES   = 20'd40000
)(
    input               glblclk,  // 处理时钟
    input               i_rst_n,  // 低有效复位

    input  [15:0]       i_data0,         // 前相数据
    input  [15:0]       i_data1,         // 后相数据
    input               i_data_valid,  // 数据有效
    input  [15:0]       i_threshold,  // 判别阈值
    input               i_enable,  // 使能信号

    output [15:0]       o_peak_in,  // 寻峰输入
    output [15:0]       o_data0_aligned, // 前相对齐数据
    output [15:0]       o_data1_aligned, // 后相对齐数据
    output              o_data_valid_aligned, // 对齐数据有效

    output [15:0]       o_baseline,  // 基线输出
    output              o_baseline_valid,  // 基线有效
    output [15:0]       o_peak_data,  // 峰值数据
    output              o_trig,  // 触发标志
    output [15:0]       o_critical,  // 判别条件
    output [4:0]        o_state_dbg,  // 状态值
    output              o_baseline_en_dbg,  // 基线采样使能
    output wire o_prefilter_done,
    output              o_trig_early  // 提前触发
);

//==============================================================================
// 1. 两相合并
//    基线：使用两相均值
//    寻峰：使用两相最大值
//==============================================================================
wire [16:0] sum2;
wire [15:0] avg2;
wire [15:0] max2;

assign sum2 = {1'b0, i_data0} + {1'b0, i_data1};
assign avg2 = sum2[16:1];
assign max2 = (i_data0 > i_data1) ? i_data0 : i_data1;

// bl_in、pk_in均比原始输入延迟1拍。
// bl_valid必须同步延迟，否则数据和有效信号在间歇有效场景下可能错位。
reg [15:0] bl_in;
reg [15:0] pk_in;
reg        bl_valid;

always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        bl_in    <= 16'h8000;
        pk_in    <= 16'h8000;
        bl_valid <= 1'b0;
    end else begin
        bl_in    <= avg2;
        pk_in    <= max2;
        bl_valid <= i_data_valid;
    end
end

assign o_peak_in = pk_in;

//==============================================================================
// 2. 动态基线
//==============================================================================
wire [15:0] baseline;
wire        baseline_ok;
wire        bl_en;

DynamicBaseLine #(
    .DATA_W   (16),
    .WIN_LOG2 (4)
) baseline_inst (
    .glblclk          (glblclk),
    .i_rst_n          (i_rst_n),
    .i_data           (bl_in),
    .i_data_valid     (bl_valid),
    .i_baseline_en    (bl_en),
    .o_baseline       (baseline),
    .o_baseline_valid (baseline_ok)
);

assign o_baseline       = baseline;
assign o_baseline_valid = baseline_ok;

//==============================================================================
// 3. 原始两相数据与寻峰数据延迟3拍
//    v3与d0_3、d1_3严格配套，送入分类器时应使用v3，不能再使用顶层adc_dv。
//==============================================================================
reg [15:0] pk_d1;
reg [15:0] pk_d2;
reg [15:0] pk_d3;

reg [15:0] d0_1;
reg [15:0] d0_2;
reg [15:0] d0_3;

reg [15:0] d1_1;
reg [15:0] d1_2;
reg [15:0] d1_3;

reg        v1;
reg        v2;
reg        v3;

always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        pk_d1 <= 16'h8000;
        pk_d2 <= 16'h8000;
        pk_d3 <= 16'h8000;

        d0_1  <= 16'h8000;
        d0_2  <= 16'h8000;
        d0_3  <= 16'h8000;

        d1_1  <= 16'h8000;
        d1_2  <= 16'h8000;
        d1_3  <= 16'h8000;

        v1    <= 1'b0;
        v2    <= 1'b0;
        v3    <= 1'b0;
    end else begin
        pk_d1 <= pk_in;
        pk_d2 <= pk_d1;
        pk_d3 <= pk_d2;

        d0_1  <= i_data0;
        d0_2  <= d0_1;
        d0_3  <= d0_2;

        d1_1  <= i_data1;
        d1_2  <= d1_1;
        d1_3  <= d1_2;

        v1    <= i_data_valid;
        v2    <= v1;
        v3    <= v2;
    end
end

assign o_data0_aligned      = d0_3;
assign o_data1_aligned      = d1_3;
assign o_data_valid_aligned = v3;

//==============================================================================
// 4. 寻峰
//==============================================================================
findpeak_tritium findpeak_inst (
 .clk(glblclk),.rst_n(i_rst_n),.enable(i_enable),.data_valid(v3),.baseline_valid(baseline_ok),
 .data0(d0_3),.data1(d1_3),.baseline(baseline),.threshold(i_threshold),
 .baseline_enable(bl_en),.early(o_trig_early),.accepted(o_trig),.decision_valid(o_prefilter_done),
 .peak(o_peak_data),.critical(o_critical),.state_debug(o_state_dbg));
assign o_baseline_en_dbg = bl_en;

endmodule