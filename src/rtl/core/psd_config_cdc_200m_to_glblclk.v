`timescale 1ns / 1ps
`default_nettype none

// =============================================================================
// psd_config_cdc_200m_to_glblclk
//
// 将 command_parser_9byte 在 CLK_200M 域产生的 CMD27/CMD28 动态配置
// 安全送到 glblclk(当前工程250MHz)处理域。
//
// CDC 方法：
//   源域：参数先锁存到 hold 寄存器，再翻转 toggle。
//   目标域：参数总线两级同步，toggle 三级同步；检测 toggle 变化后更新配置。
//   因 toggle 比数据多一级同步，因此更新时数据已经稳定。
//
// CMD27: total_gate_cycles = 1..32767，1个有效处理cycle=4ns(250MHz)
// CMD28: psd_threshold_x100 = 1..99，实际阈值 = value / 100.0
// =============================================================================
module psd_config_cdc_200m_to_glblclk #(
    parameter [15:0] DEFAULT_TOTAL_GATE_CYC      = 16'd256,
    parameter [15:0] DEFAULT_PSD_THRESHOLD_X100 = 16'd70
)(
    // -------------------------------------------------------------------------
    // Source: CLK_200M command domain
    // -------------------------------------------------------------------------
    input  wire        i_clk_200m,  // 二百兆时钟
    input  wire        i_rst_n_200m,  // 二百兆域复位

    input  wire [15:0] i_total_gate_cycles_200m,  // 总积分门宽
    input  wire        i_total_gate_valid_200m,  // 积分门更新有效

    input  wire [15:0] i_psd_threshold_x100_200m,  // 判别阈值
    input  wire        i_psd_threshold_valid_200m,  // 阈值更新有效

    // -------------------------------------------------------------------------
    // Destination: glblclk processing domain
    // -------------------------------------------------------------------------
    input  wire        i_glblclk,  // 处理时钟
    input  wire        i_rst_n_glbl,  // 处理域复位

    output reg  [15:0] o_total_gate_cycles_glbl,  // 总积分门宽
    output reg         o_total_gate_update_glbl,  // 总积分门宽

    output reg  [15:0] o_psd_threshold_x100_glbl,  // 判别阈值
    output reg         o_psd_threshold_update_glbl  // 判别阈值
);

// =============================================================================
// 1. Source-domain shadow + toggle
// =============================================================================
reg [15:0] total_gate_hold_200m;
reg [15:0] psd_threshold_hold_200m;
reg        total_gate_tgl_200m;
reg        psd_threshold_tgl_200m;

always @(posedge i_clk_200m) begin
    if (!i_rst_n_200m) begin
        total_gate_hold_200m      <= DEFAULT_TOTAL_GATE_CYC;
        psd_threshold_hold_200m   <= DEFAULT_PSD_THRESHOLD_X100;
        total_gate_tgl_200m       <= 1'b0;
        psd_threshold_tgl_200m    <= 1'b0;
    end
    else begin
        if (i_total_gate_valid_200m) begin
            total_gate_hold_200m <= i_total_gate_cycles_200m;
            total_gate_tgl_200m  <= ~total_gate_tgl_200m;
        end

        if (i_psd_threshold_valid_200m) begin
            psd_threshold_hold_200m <= i_psd_threshold_x100_200m;
            psd_threshold_tgl_200m  <= ~psd_threshold_tgl_200m;
        end
    end
end

// =============================================================================
// 2. Destination-domain bus synchronizers
// =============================================================================
reg [15:0] total_gate_s1_glbl;
reg [15:0] total_gate_s2_glbl;
reg [15:0] psd_threshold_s1_glbl;
reg [15:0] psd_threshold_s2_glbl;

(* ASYNC_REG = "TRUE" *) reg [2:0] total_gate_tgl_sync_glbl;
(* ASYNC_REG = "TRUE" *) reg [2:0] psd_threshold_tgl_sync_glbl;

reg total_gate_seen_glbl;
reg psd_threshold_seen_glbl;

always @(posedge i_glblclk) begin
    if (!i_rst_n_glbl) begin
        total_gate_s1_glbl          <= DEFAULT_TOTAL_GATE_CYC;
        total_gate_s2_glbl          <= DEFAULT_TOTAL_GATE_CYC;
        psd_threshold_s1_glbl       <= DEFAULT_PSD_THRESHOLD_X100;
        psd_threshold_s2_glbl       <= DEFAULT_PSD_THRESHOLD_X100;

        total_gate_tgl_sync_glbl    <= 3'b000;
        psd_threshold_tgl_sync_glbl <= 3'b000;
        total_gate_seen_glbl        <= 1'b0;
        psd_threshold_seen_glbl     <= 1'b0;

        o_total_gate_cycles_glbl    <= DEFAULT_TOTAL_GATE_CYC;
        o_psd_threshold_x100_glbl   <= DEFAULT_PSD_THRESHOLD_X100;
        o_total_gate_update_glbl    <= 1'b0;
        o_psd_threshold_update_glbl <= 1'b0;
    end
    else begin
        // 参数总线持续同步；源域会一直保持到下一次同类命令。
        total_gate_s1_glbl    <= total_gate_hold_200m;
        total_gate_s2_glbl    <= total_gate_s1_glbl;
        psd_threshold_s1_glbl <= psd_threshold_hold_200m;
        psd_threshold_s2_glbl <= psd_threshold_s1_glbl;

        // toggle 比数据多一级同步。
        total_gate_tgl_sync_glbl <= {
            total_gate_tgl_sync_glbl[1:0], total_gate_tgl_200m
        };
        psd_threshold_tgl_sync_glbl <= {
            psd_threshold_tgl_sync_glbl[1:0], psd_threshold_tgl_200m
        };

        o_total_gate_update_glbl    <= 1'b0;
        o_psd_threshold_update_glbl <= 1'b0;

        if (total_gate_tgl_sync_glbl[2] != total_gate_seen_glbl) begin
            total_gate_seen_glbl     <= total_gate_tgl_sync_glbl[2];
            o_total_gate_cycles_glbl <= total_gate_s2_glbl;
            o_total_gate_update_glbl <= 1'b1;
        end

        if (psd_threshold_tgl_sync_glbl[2] != psd_threshold_seen_glbl) begin
            psd_threshold_seen_glbl     <= psd_threshold_tgl_sync_glbl[2];
            o_psd_threshold_x100_glbl   <= psd_threshold_s2_glbl;
            o_psd_threshold_update_glbl <= 1'b1;
        end
    end
end

endmodule

`default_nettype wire
