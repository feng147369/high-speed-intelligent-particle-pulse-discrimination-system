`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Top_spectrum_v3
//
// 在原 Top_spectrum 的“能谱累计 + 双RAM镜像”结构基础上，只替换发送侧：
// SpectrumOperate + RAM_data + RAM_OUT 继续保留；
// 原 AcquiringReaTimeEnergySpectrum 不再负责组旧协议包；
// spectrum_raw_reader_v2 只把当前 bin_count 个 32bit 道计数写入 FIFO_spectrum。
//
// 最终协议包头/包长/0C/90/91/0AA0 由 Top_DualSpectrum_v2 在 200MHz 域生成。
// ============================================================================
module Top_spectrum #(
    parameter integer FIFO_READS_LSB_FIRST = 0
)(
    input  wire        SYS_clk,  // 系统时钟
    input  wire        SYS_rst,  // 系统复位
    input  wire        CLK_200M,  // 二百兆时钟
    input wire RST,

// CMD24切档：刷新发送reader/FIFO
    input wire i_output_flush,

// CMD24切档：是否清累计能谱
    input wire i_accum_clear,
    input  wire [7:0]  data_AorB_r,  // 输入数据
    input  wire        voltage_range,  // 电压量程
    input  wire [31:0] output_multiply,  // 输出缩放系数
    input  wire [31:0] timecount,  // 时间戳

    input  wire [15:0] datain,  // 输入数据
    input  wire        datain_en,  // 输入有效

    input  wire        cmd_control,  // 命令控制
    input  wire        i_output_enable,  // 输出使能
    input  wire        instr_done,  // 指令完成
    input  wire [15:0] cmd_spectrumperiod,  // 能谱控制信号

    // 已经在 SYS_clk 域稳定的 CMD24 实际道址数
    input  wire [13:0] i_spectrum_bins_sys,  // 能谱道数

    input  wire        SpectrumData_rden,  // 能谱读取使能
    input  wire        key_cap_rst,  // 复位信号

    output wire        SpectrumData_empty,  // 能谱数据为空
    output wire        spectrum_ren,  // 能谱读出状态
    output wire [7:0]  SpectrumData_out,  // 能谱输出数据
    output wire        SpectrumData_valid,  // 能谱数据有效
    output wire [31:0] spec_rdcnt,  // 能谱剩余字节

    output wire [11:0] o_dbg_state,  // 调试状态
    output wire [13:0] o_dbg_addr,  // 调试地址
    output wire [13:0] o_dbg_tmp_addr,  // 调试暂存地址
    output wire [31:0] o_dbg_tmp_dataout,  // 调试累计值
    output wire [3:0]  o_dbg_count,  // 调试计数
    output wire        o_dbg_flag_instr,  // 调试信号
    output wire [15:0] o_dbg_raw_dataout,  // 原始调试数据
    output wire        o_dbg_raw_dataouten,  // 原始调试数据
    output wire [13:0] o_dbg_raw_addr,  // 原始调试地址
    output wire [3:0]  o_dbg_reader_state,  // 调试状态
    
        // ===== 新增：8192问题调试 =====
    output wire        o_dbg_raw_fifo_full,  // 调试满标志
    output wire        o_dbg_raw_done_pulse  // 调试完成脉冲
);

    wire unused_key_cap_rst      = key_cap_rst;
    wire unused_fifo_order_param = (FIFO_READS_LSB_FIRST != 0);
    wire [31:0] unused_timecount = timecount;
    wire [31:0] unused_multiply  = output_multiply;

    function [13:0] sanitize_bins;
        input [13:0] bins;  // 有效道数
        begin
            case (bins)
                14'd1024: sanitize_bins = 14'd1024;
                14'd2048: sanitize_bins = 14'd2048;
                14'd4096: sanitize_bins = 14'd4096;
                14'd8192: sanitize_bins = 14'd8192;
                default : sanitize_bins = 14'd4096;
            endcase
        end
    endfunction

    wire [13:0] spectrum_bins_sys = sanitize_bins(i_spectrum_bins_sys);
// ========================================================================
// CMD24 输出侧刷新
//
// i_output_flush 是 SYS_clk 域单周期脉冲。
// 异步 FIFO 的 reset 不能直接只接这个单周期脉冲，
// 因此在 SYS_clk 域将其拉长 16 个周期。
// ========================================================================
reg  [4:0] output_flush_count;
wire       output_flush_active;

assign output_flush_active =
    i_output_flush || (output_flush_count != 5'd0);

always @(posedge SYS_clk or negedge SYS_rst) begin
    if (!SYS_rst) begin
        output_flush_count <= 5'd0;
    end
    else if (RST) begin
        output_flush_count <= 5'd0;
    end
    else if (i_output_flush) begin
        output_flush_count <= 5'd16;
    end
    else if (output_flush_count != 5'd0) begin
        output_flush_count <= output_flush_count - 1'b1;
    end
end
    // 实时累计固定按最大8192道工作。
    // CMD24只在发送侧做相邻bin合并，数学上等价于旧版 addr >> vary_located。
    // 但不会把动态档位带入250MHz实时事件地址关键路径。
    localparam [7:0] ACCUM_VARY_LOCATED = 8'd1;

    // ========================================================================
    // 1. 能谱累计
    // ========================================================================
    wire        SOramEn_data;
    wire        SOramWea_data;
    wire        SOramRSTA_data;
    wire [31:0] RAM2SO_dout_data;
    wire [13:0] SOramAddr_data;
    wire [31:0] SOData2ram_data;

    wire        SOramEn_out;
    wire        SOramWea_out;
    wire        SOramRSTA_out;
    wire [13:0] SOramAddr_out;
    wire [31:0] SOData2ram_out;

    SpectrumOperate SpectrumOperate_inst (
        .clkin              (SYS_clk),
        .rst_n              (SYS_rst),
        .vary_located       (ACCUM_VARY_LOCATED),
        .data_AorB_r        (data_AorB_r),
        .voltage_range      (voltage_range),
        .FPDatain           (datain),
        .FPEn               (datain_en),
        .instr_done         (instr_done),
        .cmd_control        (cmd_control),
        .cmd_spectrumperiod (cmd_spectrumperiod),

        .ramDatain          (RAM2SO_dout_data),
        .ramEn_data         (SOramEn_data),
        .ramEn_out          (SOramEn_out),
        .ramAddr_data       (SOramAddr_data),
        .ramAddr_out        (SOramAddr_out),
        .Data2ram_data      (SOData2ram_data),
        .Data2ram_out       (SOData2ram_out),
        .ramRSTA_data       (SOramRSTA_data),
        .RST (RST || i_accum_clear),
        .ramRSTA_out        (SOramRSTA_out),
        .ramWea_data        (SOramWea_data),
        .ramWea_out         (SOramWea_out),

        .dbg_state          (o_dbg_state),
        .dbg_addr           (o_dbg_addr),
        .dbg_tmp_addr       (o_dbg_tmp_addr),
        .dbg_tmp_dataout    (o_dbg_tmp_dataout),
        .dbg_count          (o_dbg_count),
        .dbg_flag_instr     (o_dbg_flag_instr)
    );

    RAM_data RAM_data_inst (
        .clka  (SYS_clk),
        .ena   (SOramEn_data),
        .wea   (SOramWea_data),
        .addra (SOramAddr_data),
        .dina  (SOData2ram_data),
        .douta (RAM2SO_dout_data)
    );

    // ========================================================================
    // 2. 输出镜像 RAM
    // ========================================================================
    wire        raw_ram_en;
    wire [13:0] raw_ram_addr;
    wire [31:0] raw_ram_data;

    RAM_OUT RAM_OUT_inst (
        .clka  (SYS_clk),
        .ena   (SOramEn_out),
        .wea   (SOramWea_out),
        .addra (SOramAddr_out),
        .dina  (SOData2ram_out),

        .clkb  (SYS_clk),
        .enb   (raw_ram_en),
        .addrb (raw_ram_addr),
        .doutb (raw_ram_data)
    );

    // ========================================================================
    // 3. 纯数据区读出 -> 现有异步 FIFO_spectrum
    // ========================================================================
    wire        raw_fifo_full;
    wire [15:0] raw_fifo_din;
    wire        raw_fifo_wr_en;
    wire        raw_done_pulse;
    wire        raw_waiting_period;

    spectrum_raw_reader_v3_rebin #(
        .PERIOD_CYCLES (100_000_000)
    ) raw_reader (
        .clk                 (SYS_clk),
        .rst_n               (SYS_rst),
        .soft_reset (RST || output_flush_active),
        .i_enable            (cmd_control && i_output_enable),
        .i_bin_count         (spectrum_bins_sys),
        .o_ram_en            (raw_ram_en),
        .o_ram_addr          (raw_ram_addr),
        .i_ram_data          (raw_ram_data),
        .i_fifo_full         (raw_fifo_full),
        .o_fifo_din          (raw_fifo_din),
        .o_fifo_wr_en        (raw_fifo_wr_en),
        .o_packet_done_pulse (raw_done_pulse),
        .o_waiting_period    (raw_waiting_period),
        .o_state_dbg         (o_dbg_reader_state)
    );

    assign spectrum_ren       = raw_waiting_period;
    assign o_dbg_raw_dataout  = raw_fifo_din;
    assign o_dbg_raw_dataouten= raw_fifo_wr_en;
    assign o_dbg_raw_addr     = raw_ram_addr;
// ============================================================
// DEBUG ONLY：观察 raw_reader -> FIFO_spectrum 写侧
// 不参与任何功能控制
// ============================================================
assign o_dbg_raw_fifo_full  = raw_fifo_full;
assign o_dbg_raw_done_pulse = raw_done_pulse;
    // 仅为了让综合器明确看到该调试脉冲已被有意保留
    wire unused_raw_done = raw_done_pulse;

    // 原工程 spec_rdcnt 只接了13bit，这里保持接口兼容。
    assign spec_rdcnt[31:13] = 19'd0;

    FIFO_spectrum FIFO_spectrum_inst (
        .rst (~SYS_rst || RST || output_flush_active),
        .wr_clk        (SYS_clk),
        .rd_clk        (CLK_200M),
        .din           (raw_fifo_din),
        .wr_en         (raw_fifo_wr_en),
        .rd_en         (SpectrumData_rden),
        .dout          (SpectrumData_out),
        .full          (raw_fifo_full),
        .empty         (SpectrumData_empty),
        .valid         (SpectrumData_valid),
        .rd_data_count (spec_rdcnt[12:0])
    );

endmodule

`default_nettype wire
