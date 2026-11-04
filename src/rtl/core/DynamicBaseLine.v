`timescale 1ns / 1ps

module DynamicBaseLine #(
    parameter DATA_W   = 16,           
    parameter WIN_LOG2 = 4             // 窗口大小 = 2^WIN_LOG2 = 16 点
)(
    // -------- 时钟与复位 --------
    input                   glblclk,        // 处理时钟
    input                   i_rst_n,        // 低有效复位

    // -------- ADC 数据输入 --------
    // 格式: offset binary, [15:2]=14bit有效, [1]=OR位, [0]=0
    input  [DATA_W-1:0]     i_data,         // 输入数据
    input                   i_data_valid,   // 数据有效
    input                   i_baseline_en,  // 基线采样使能
    output reg [DATA_W-1:0] o_baseline,  // 基线输出
    output reg              o_baseline_valid  // 基线有效
);

localparam WIN_SIZE  = (1 << WIN_LOG2);    // 滑动窗口点数: 16
localparam SUM_W     = DATA_W + WIN_LOG2;  // 累加器位宽: 16+4=20, 留足裕量用24

//==============================================================================
// 1. 输入数据打拍 (pipeline 延迟, 与原版一致)
//    打3拍: 补偿上级逻辑延迟, 保证与 i_baseline_en 时序对齐
//==============================================================================
reg [DATA_W-1:0] data_r1, data_r2, data_r3;
reg              valid_r1, valid_r2, valid_r3;

always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_r1  <= {DATA_W{1'b0}};
        data_r2  <= {DATA_W{1'b0}};
        data_r3  <= {DATA_W{1'b0}};
        valid_r1 <= 1'b0;
        valid_r2 <= 1'b0;
        valid_r3 <= 1'b0;
    end else begin
        data_r1  <= i_data;
        data_r2  <= data_r1;
        data_r3  <= data_r2;
        valid_r1 <= i_data_valid;
        valid_r2 <= valid_r1;
        valid_r3 <= valid_r2;
    end
end

//==============================================================================
// 2. 初始化计数器
//    上电后等待 WIN_SIZE+2 个有效采样点填满窗口
//    期间 o_baseline_valid=0, 基线输出不可信
//==============================================================================
reg [9:0] init_cnt;

always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        init_cnt         <= 10'd0;
        o_baseline_valid <= 1'b0;
    end else begin
        if (valid_r3 && !o_baseline_valid) begin
            if (init_cnt < (WIN_SIZE + 4)) begin   // +4 留pipeline裕量
                init_cnt <= init_cnt + 1'b1;
            end else begin
                o_baseline_valid <= 1'b1;
            end
        end
    end
end

//==============================================================================
// 3. 滑动窗口缓存 & 递推累加 (含基线冻结)
//    算法: new_sum = old_sum + new_data - oldest_data
//    窗口大小 WIN_SIZE=16, 均值 = sum >> WIN_LOG2 (= sum / 16)
//
// 注意: AD9694 输出 offset binary
//   中码 0x8000 对应 0V (满量程中点, 1.80V 直流偏置)
//   信号叠加在中码附近波动
//   基线在无信号时应稳定在 0x8000 附近
//
// 基线冻结: i_baseline_en = 0 时停止窗口更新, 基线保持不变
//==============================================================================

// 滑动窗口存储 (16 × 16bit)
reg [DATA_W-1:0] window [0:WIN_SIZE-1];

// 累加寄存器 (额外4bit防溢出)
reg [23:0] sum_data;

// 临时基线 (求均值后)
reg [DATA_W-1:0] tmp_baseline;

// 窗口指针 (循环写入)
reg [WIN_LOG2-1:0] wr_ptr;          // 4bit, 自动对 16 取模

integer k;
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sum_data <= (24'd32768 << WIN_LOG2);
        tmp_baseline <= 16'h8000;   // 复位基线预置为中码 (offset binary 零点)
        wr_ptr       <= {WIN_LOG2{1'b0}};
        for (k = 0; k < WIN_SIZE; k = k + 1)
            window[k] <= 16'h8000; // 窗口预填中码, 避免上电基线跳变
    end else begin
        // 数据有效且 (基线使能有效 或 尚未完成初始化) 时更新窗口
        if (valid_r3 && (i_baseline_en || !o_baseline_valid)) begin
            sum_data     <= sum_data
                            + {8'd0, data_r3}           // 新数据
                            - {8'd0, window[wr_ptr]};   // 即将被覆盖的最旧数据

            // 覆盖最旧数据
            window[wr_ptr] <= data_r3;

            wr_ptr <= wr_ptr + 1'b1;

            tmp_baseline <= sum_data[DATA_W-1+WIN_LOG2 : WIN_LOG2];
        end
    end
end

//==============================================================================
// 4. 基线输出寄存器
//==============================================================================
always @(posedge glblclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_baseline <= 16'h8000;
    end else begin
        if (o_baseline_valid) begin
            o_baseline <= tmp_baseline;
        end
    end
end

endmodule