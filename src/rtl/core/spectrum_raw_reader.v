`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// spectrum_raw_reader_v3_rebin
//
// 设计目标：
//   1. SpectrumOperate 永远按最大 8192 道累计，避免 CMD24 动态档位进入
//      250MHz 实时事件地址关键路径。
//   2. 输出时根据 CMD24 将相邻 8192 基础道做等价合并：
//        8192 -> 每1道输出1道
//        4096 -> 每2道求和
//        2048 -> 每4道求和
//        1024 -> 每8道求和
//      这与原 SpectrumOperate 的 addr >> vary_located 数学等价。
//   3. 只输出纯 32bit 能谱数据区；5A A5 / 0C / LEN / BINS / 90/91 / 0A A0
//      由 Top_DualSpectrum_v3 在 200MHz 域统一组包。
//   4. RAM 顺序扫描 0..8191，不使用动态 barrel shift。
//   5. 32bit 分两次 16bit 写入 FIFO_spectrum；按 Xilinx FIFO Generator
//      宽度转换的 MSB-first 顺序，先写高16，再写低16。
// ============================================================================
module spectrum_raw_reader_v3_rebin #(
    parameter integer PERIOD_CYCLES = 100_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        soft_reset,

    input  wire        i_enable,
    input  wire [13:0] i_bin_count,

    // 8192道镜像 RAM 读口
    output reg         o_ram_en,
    output reg  [13:0] o_ram_addr,
    input  wire [31:0] i_ram_data,

    // 16bit写 / 8bit读 FIFO
    input  wire        i_fifo_full,
    output reg  [15:0] o_fifo_din,
    output reg         o_fifo_wr_en,

    output reg         o_packet_done_pulse,
    output wire        o_waiting_period,
    output wire [3:0]  o_state_dbg
);

    localparam [3:0]
        S_IDLE     = 4'd0,
        S_RAM_REQ  = 4'd1,
        S_RAM_WAIT = 4'd2,
        S_RAM_CAP  = 4'd3,
        S_OUT_HI   = 4'd4,
        S_OUT_LO   = 4'd5,
        S_DELAY    = 4'd6,
        // Added: wait for FIFO acceptance of registered wr_en on next clk.
        S_OUT_HI_ACK = 4'd7,
        S_OUT_LO_ACK = 4'd8;

    reg [3:0] state;

    reg [13:0] out_bin_count_latched;
    reg [2:0]  group_last_latched;     // 0/1/3/7
    reg [13:0] base_ram_addr;          // 始终顺序 0..8191
    reg [13:0] out_bin_index;
    reg [2:0]  group_index;

    reg [31:0] group_acc;
    reg [31:0] data_buf;
    reg [31:0] delay_count;

    function [13:0] sanitize_bins;
        input [13:0] bins;
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

    function [2:0] bins_to_group_last;
        input [13:0] bins;
        begin
            case (bins)
                14'd8192: bins_to_group_last = 3'd0; // 1
                14'd4096: bins_to_group_last = 3'd1; // 2
                14'd2048: bins_to_group_last = 3'd3; // 4
                14'd1024: bins_to_group_last = 3'd7; // 8
                default : bins_to_group_last = 3'd1;
            endcase
        end
    endfunction

    wire [31:0] group_sum_next = group_acc + i_ram_data;

    assign o_waiting_period = (state == S_DELAY);
    assign o_state_dbg      = state;

    always @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            state                 <= S_IDLE;
            out_bin_count_latched <= 14'd4096;
            group_last_latched    <= 3'd1;
            base_ram_addr         <= 14'd0;
            out_bin_index         <= 14'd0;
            group_index           <= 3'd0;
            group_acc             <= 32'd0;
            data_buf              <= 32'd0;
            delay_count           <= 32'd0;

            o_ram_en              <= 1'b0;
            o_ram_addr            <= 14'd0;
            o_fifo_din            <= 16'd0;
            o_fifo_wr_en          <= 1'b0;
            o_packet_done_pulse   <= 1'b0;
        end
        else begin
            o_fifo_wr_en        <= 1'b0;
            o_packet_done_pulse <= 1'b0;

            case (state)
                S_IDLE: begin
                    o_ram_en      <= 1'b0;
                    o_ram_addr    <= 14'd0;
                    base_ram_addr <= 14'd0;
                    out_bin_index <= 14'd0;
                    group_index   <= 3'd0;
                    group_acc     <= 32'd0;
                    delay_count   <= 32'd0;

                    if (i_enable) begin
                        out_bin_count_latched <= sanitize_bins(i_bin_count);
                        group_last_latched    <= bins_to_group_last(
                                                    sanitize_bins(i_bin_count)
                                                 );
                        state <= S_RAM_REQ;
                    end
                end

                // RAM_OUT 是同步读口；地址按 0..8191 顺序走
                S_RAM_REQ: begin
                    o_ram_en   <= 1'b1;
                    o_ram_addr <= base_ram_addr;
                    state      <= S_RAM_WAIT;
                end

                S_RAM_WAIT: begin
                    o_ram_en   <= 1'b1;
                    o_ram_addr <= base_ram_addr;
                    state      <= S_RAM_CAP;
                end

                S_RAM_CAP: begin
                    o_ram_en <= 1'b0;

                    if (group_index == group_last_latched) begin
                        // 本输出道的最后一个基础道
                        data_buf    <= group_sum_next;
                        group_acc   <= 32'd0;
                        group_index <= 3'd0;
                        state       <= S_OUT_HI;
                    end
                    else begin
                        group_acc     <= group_sum_next;
                        group_index   <= group_index + 1'b1;
                        base_ram_addr <= base_ram_addr + 1'b1;
                        state         <= S_RAM_REQ;
                    end
                end

                // FIFO Generator 16->8 宽度转换按 MSB 到 LSB 读出，
                // 所以高16先写即可得到 D31:24,D23:16,D15:8,D7:0。
                // Only schedule a registered FIFO write here. FIFO consumes
                // o_fifo_wr_en on the NEXT rising edge, not on this edge.
                S_OUT_HI: begin
                    if (!i_fifo_full) begin
                        o_fifo_din   <= data_buf[31:16];
                        o_fifo_wr_en <= 1'b1;
                        state        <= S_OUT_HI_ACK;
                    end
                end

                // At this edge FIFO samples previous-cycle wr_en and full.
                // If full was high, the pending write was rejected; retry.
                S_OUT_HI_ACK: begin
                    if (!i_fifo_full)
                        state <= S_OUT_LO;
                    else
                        state <= S_OUT_HI;
                end

                S_OUT_LO: begin
                    if (!i_fifo_full) begin
                        o_fifo_din   <= data_buf[15:0];
                        o_fifo_wr_en <= 1'b1;
                        state        <= S_OUT_LO_ACK;
                    end
                end

                // Advance bin index / issue done only after low 16b was
                // actually accepted by FIFO (not merely requested).
                S_OUT_LO_ACK: begin
                    if (!i_fifo_full) begin
                        if (out_bin_index == (out_bin_count_latched - 1'b1)) begin
                            o_packet_done_pulse <= 1'b1;
                            delay_count         <= 32'd0;
                            state               <= S_DELAY;
                        end
                        else begin
                            out_bin_index <= out_bin_index + 1'b1;

                            // Advance RAM address only after full 32-bit bin
                            // has reached the FIFO.
                            base_ram_addr <= base_ram_addr + 1'b1;
                            state         <= S_RAM_REQ;
                        end
                    end
                    else begin
                        state <= S_OUT_LO;
                    end
                end

                S_DELAY: begin
                    o_ram_en <= 1'b0;

                    if (PERIOD_CYCLES <= 1) begin
                        delay_count <= 32'd0;
                        state       <= S_IDLE;
                    end
                    else if (delay_count >= PERIOD_CYCLES - 1) begin
                        delay_count <= 32'd0;
                        state       <= S_IDLE;
                    end
                    else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                default: begin
                    state        <= S_IDLE;
                    o_ram_en     <= 1'b0;
                    o_fifo_wr_en <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
