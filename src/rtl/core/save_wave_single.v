`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// save_wave_single
//
// 保持原模块名。
// CMD23最终语义：i_cap_num=N，N为实际16bit ADC采样点数，范围0~2047。
//
// 文档正式Wave包格式（Byte流）：
//   Byte0      5A
//   Byte1      A5
//   Byte2      0A              // Wave标识
//   Byte3      LEN_H
//   Byte4      LEN_L           // 完整包总字节数
//   Byte5      N_H
//   Byte6      N_L             // 实际采样点数
//   Byte7...   N个16bit ADC样点，大端：HIGH -> LOW
//   Last-1     0A
//   Last       A0
//
// 完整包长度：
//   2 + 1 + 2 + 2 + 2*N + 2 = 2*N + 9 Byte
//
// 最大N=2047：
//   4103 Byte
//
// 注意：
//   新包是奇数字节长度，因此本模块输出改为8bit Byte流。
//   fifo_wave_async必须改成 8bit write / 8bit read。
// ============================================================================
module save_wave_single #(
    parameter GATE_CAPABLE = 0,
    parameter TIMESTAMPED = 0,
    parameter integer GATE_PRE_SAMPLES = 24,
    parameter [7:0]   CHANNEL_ID  = 8'h01, // 兼容旧顶层，正式包不再携带
    parameter integer CAP_NUM_P   = 256,   // 兼容旧顶层，不再决定长度
    parameter integer PRE_NUM     = 92,    // 16bit样点数
    parameter [31:0]  DEAD_CYCLES = 32'd200
)(
    input wire i_gate_enable, i_gate_valid, i_gate_accept,
    output wire o_capture_ready, o_busy,
    output reg o_done,
    input  wire        i_clk,  // 工作时钟
    input  wire        i_rst_n,  // 低有效复位

    input  wire [15:0] i_cap_num,  // 采样点数

    input  wire [47:0] i_time_cnt,  // 时间戳
    input  wire [15:0] i_data0,  // 前相数据
    input  wire [15:0] i_data1,  // 后相数据
    input  wire        i_data_valid,  // 数据有效
    input  wire        i_wave_pos_flag,  // 波形控制信号

    input  wire        i_fifo_full,  // FIFO满标志

    output wire [7:0]  o_data,  // 输出数据
    output wire        o_wr_en  // 写使能
);

    localparam integer MEM_PAIRS = 1024;
    localparam integer ADDR_W    = 10;

    localparam [3:0]
        ST_WAIT_GATE = 4'd11,
        ST_IDLE       = 4'd0,
        ST_WAIT_POST  = 4'd1,
        ST_HEADER     = 4'd2,
        ST_MEM_REQ    = 4'd3,
        ST_MEM_WAIT   = 4'd4,
        ST_SAMPLE0_HI = 4'd5,
        ST_SAMPLE0_LO = 4'd6,
        ST_SAMPLE1_HI = 4'd7,
        ST_SAMPLE1_LO = 4'd8,
        ST_TAIL       = 4'd9,
        ST_DEAD       = 4'd10;

    reg [3:0] state;

    // ------------------------------------------------------------------------
    // 1024 x 32bit ring buffer：每项={data1,data0}
    // 总容量2048个16bit样点，可覆盖最大N=2047。
    // ------------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] reservoir [0:MEM_PAIRS-1];

    reg [ADDR_W-1:0] wr_ptr;

    reg               mem_rd_en;
    reg [ADDR_W-1:0]  mem_rd_addr;
    reg [31:0]        mem_rd_data;

    wire capture_ram_write =
        i_rst_n &&
        i_data_valid &&
        ((state == ST_IDLE) || (state == ST_WAIT_POST));

    always @(posedge i_clk) begin
        if (capture_ram_write)
            reservoir[wr_ptr] <= {i_data1, i_data0};

        if (mem_rd_en)
            mem_rd_data <= reservoir[mem_rd_addr];
    end

    // ------------------------------------------------------------------------
    // CMD23清洗：最终范围0~2047
    // ------------------------------------------------------------------------
    // Configuration-only pipeline. Keep it clocking during capture reset:
    // the existing CMD23 reset window lets both stages settle before START.
    // No pipeline stage is inserted in the ADC/trigger/event data path.
    wire [11:0] cap_samples_input =
        (i_cap_num > 16'd2047) ? 12'd2047 : i_cap_num[11:0];

    function [11:0] calc_pre_samples;
        input [11:0] n;  // 循环索引
        integer p;
        begin
            if (n == 0) begin
                calc_pre_samples = 12'd0;
            end
            else begin
                p = GATE_CAPABLE ? GATE_PRE_SAMPLES : PRE_NUM;
                if (p > (n - 1))
                    p = n - 1;

                // 窗口起点对齐data0/pair边界。
                p = p & 16'hFFFE;
                calc_pre_samples = p[11:0];
            end
        end
    endfunction

    reg [15:0] cfg_input_s1 = 16'd256;
    reg [15:0] cfg_input_s2 = 16'd256;
    reg [11:0] cap_samples_s1 = 12'd256;
    reg [11:0] pre_samples_s1 = calc_pre_samples(12'd256);
    reg [11:0] cap_samples_cfg = 12'd256;
    reg [11:0] pre_samples_cfg = calc_pre_samples(12'd256);
    reg [10:0] post_pair_need_cfg =
        (12'd255 - calc_pre_samples(12'd256)) >> 1;

    wire [11:0] last_offset_s1 = (cap_samples_s1 == 0)
        ? 12'd0 : (cap_samples_s1 - 12'd1 - pre_samples_s1);

    always @(posedge i_clk) begin
        cfg_input_s1       <= i_cap_num;
        cap_samples_s1     <= cap_samples_input;
        pre_samples_s1     <= calc_pre_samples(cap_samples_input);

        cfg_input_s2       <= cfg_input_s1;
        cap_samples_cfg    <= cap_samples_s1;
        pre_samples_cfg    <= pre_samples_s1;
        post_pair_need_cfg <= last_offset_s1 >> 1;
    end

    wire [15:0] packet_len_cfg =
        ({4'd0, cap_samples_cfg} << 1) + (TIMESTAMPED ? 16'd15 : 16'd9);
    wire [10:0] pre_pairs_cfg = pre_samples_cfg >> 1;
    // Never accept a new trigger with partially updated configuration.
    // After a change, two clocks (8 ns at 250 MHz) prepare the parameters.
    // Configuration registers keep settling even while i_rst_n is low.
    wire cfg_ready = (i_cap_num == cfg_input_s1) &&
                     (cfg_input_s1 == cfg_input_s2);

    // ------------------------------------------------------------------------
    // Trigger edge
    // ------------------------------------------------------------------------
    reg r_wave_pos_d1;

    always @(posedge i_clk) begin
        if (!i_rst_n)
            r_wave_pos_d1 <= 1'b0;
        else if (i_data_valid)
            r_wave_pos_d1 <= i_wave_pos_flag;
    end

    wire trig_up =
        i_data_valid &&
        i_wave_pos_flag &&
        !r_wave_pos_d1;

    reg [11:0] history_samples;

    wire history_ready =
        (history_samples >= pre_samples_cfg);

    wire accept_trig =
        (state == ST_IDLE) &&
        cfg_ready &&
        trig_up &&
        history_ready &&
        !i_fifo_full;

    assign o_capture_ready = i_rst_n && state==ST_IDLE && cfg_ready && history_ready && !i_fifo_full;
    assign o_busy = state!=ST_IDLE;
    reg gate_event, gate_seen, gate_accept;
    always @(posedge i_clk) begin
        if(!i_rst_n)begin gate_event<=0;gate_seen<=0;gate_accept<=0;end
        else begin
            if(accept_trig)begin gate_event<=GATE_CAPABLE && i_gate_enable;gate_seen<=0;end
            if(i_gate_valid && gate_event)begin gate_seen<=1;gate_accept<=i_gate_accept;end
        end
    end
    // ------------------------------------------------------------------------
    // Event latch
    // ------------------------------------------------------------------------
    reg [11:0] cap_samples_latched;
    reg [15:0] packet_len_latched;

    reg [10:0] post_pair_need_latched;
    reg [10:0] post_pairs_seen;

    reg [ADDR_W-1:0] start_pair_addr;
    reg [ADDR_W-1:0] read_pair_addr;

    reg [11:0] samples_sent;
    reg [3:0]  header_idx;
    reg [47:0] event_time_latched;
    reg        tail_idx;
    reg [31:0] dead_cnt;

    // ------------------------------------------------------------------------
    // Byte output
    // ------------------------------------------------------------------------
    reg [7:0] out_data_c;
    reg       out_wr_c;

    assign o_data  = out_data_c;
    assign o_wr_en = out_wr_c;

    always @(*) begin
        out_data_c = 8'h00;
        out_wr_c   = 1'b0;

        case (state)
            ST_HEADER: begin
                if (!i_fifo_full) begin
                    out_wr_c = 1'b1;
                    case (header_idx)
                        4'd0: out_data_c = 8'h5A;
                        4'd1: out_data_c = 8'hA5;
                        4'd2: out_data_c = TIMESTAMPED ? 8'h0D : 8'h0A;
                        4'd3: out_data_c = packet_len_latched[15:8];
                        4'd4: out_data_c = packet_len_latched[7:0];
                        4'd5: out_data_c = {4'd0, cap_samples_latched[11:8]};
                        4'd6: out_data_c = cap_samples_latched[7:0];
                        4'd7: out_data_c = event_time_latched[47:40];
                        4'd8: out_data_c = event_time_latched[39:32];
                        4'd9: out_data_c = event_time_latched[31:24];
                        4'd10: out_data_c = event_time_latched[23:16];
                        4'd11: out_data_c = event_time_latched[15:8];
                        4'd12: out_data_c = event_time_latched[7:0];
                        default: out_data_c = 8'h00;
                    endcase
                end
            end

            ST_SAMPLE0_HI: begin
                if (!i_fifo_full) begin
                    out_wr_c   = 1'b1;
                    out_data_c = mem_rd_data[15:8];
                end
            end

            ST_SAMPLE0_LO: begin
                if (!i_fifo_full) begin
                    out_wr_c   = 1'b1;
                    out_data_c = mem_rd_data[7:0];
                end
            end

            ST_SAMPLE1_HI: begin
                if (!i_fifo_full) begin
                    out_wr_c   = 1'b1;
                    out_data_c = mem_rd_data[31:24];
                end
            end

            ST_SAMPLE1_LO: begin
                if (!i_fifo_full) begin
                    out_wr_c   = 1'b1;
                    out_data_c = mem_rd_data[23:16];
                end
            end

            ST_TAIL: begin
                if (!i_fifo_full) begin
                    out_wr_c   = 1'b1;
                    out_data_c = tail_idx ? 8'hA0 : 8'h0A;
                end
            end

            default: begin
                out_data_c = 8'h00;
                out_wr_c   = 1'b0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Ring write pointer + PRE history
    // ------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            wr_ptr          <= {ADDR_W{1'b0}};
            history_samples <= 12'd0;
        end
        else begin
            if (capture_ram_write)
                wr_ptr <= wr_ptr + 1'b1;

            if (accept_trig) begin
                history_samples <= 12'd0;
            end
            else if ((state == ST_IDLE) && i_data_valid) begin
                if (history_samples < 12'd2047) begin
                    if (history_samples <= 12'd2045)
                        history_samples <= history_samples + 12'd2;
                    else
                        history_samples <= 12'd2047;
                end
            end
            else if ((state != ST_IDLE) && (state != ST_WAIT_POST)) begin
                history_samples <= 12'd0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_done<=0;event_time_latched<=0;
            state                  <= ST_IDLE;

            mem_rd_en              <= 1'b0;
            mem_rd_addr            <= {ADDR_W{1'b0}};

            cap_samples_latched    <= 12'd256;
            packet_len_latched     <= 16'd521; // 2*256+9

            post_pair_need_latched <= 11'd81;
            post_pairs_seen        <= 11'd0;

            start_pair_addr        <= {ADDR_W{1'b0}};
            read_pair_addr         <= {ADDR_W{1'b0}};

            samples_sent           <= 12'd0;
            header_idx             <= 3'd0;
            tail_idx               <= 1'b0;
            dead_cnt               <= 32'd0;
        end
        else begin
            o_done<=0;
            mem_rd_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    samples_sent    <= 12'd0;
                    header_idx      <= 3'd0;
                    tail_idx        <= 1'b0;
                    dead_cnt        <= 32'd0;
                    post_pairs_seen <= 11'd0;

                    if (accept_trig) begin
                        event_time_latched <= i_time_cnt;
                        cap_samples_latched    <= cap_samples_cfg;
                        packet_len_latched     <= packet_len_cfg;
                        post_pair_need_latched <= post_pair_need_cfg;

                        // 当前trigger pair本拍写到reservoir[wr_ptr]
                        start_pair_addr <= wr_ptr - pre_pairs_cfg[ADDR_W-1:0];

                        if (post_pair_need_cfg == 0)
                            state <= (GATE_CAPABLE && i_gate_enable) ? ST_WAIT_GATE : ST_HEADER;
                        else
                            state <= ST_WAIT_POST;
                    end
                end

                ST_WAIT_POST: begin
                    if (i_data_valid) begin
                        if ((post_pairs_seen + 1'b1) >= post_pair_need_latched) begin
                            post_pairs_seen <= post_pairs_seen + 1'b1;
                            state <= gate_event ? ST_WAIT_GATE : ST_HEADER;
                        end
                        else begin
                            post_pairs_seen <= post_pairs_seen + 1'b1;
                        end
                    end
                end

                ST_WAIT_GATE: begin
                    if(gate_seen)begin
                        if(gate_accept)state<=ST_HEADER;
                        else begin o_done<=1;dead_cnt<=0;state<=ST_DEAD;end
                    end
                end
                // 7Byte正式头
                ST_HEADER: begin
                    if (!i_fifo_full) begin
                        if (header_idx == (TIMESTAMPED ? 4'd12 : 4'd6)) begin
                            header_idx <= 3'd0;

                            if (cap_samples_latched == 0) begin
                                tail_idx <= 1'b0;
                                state    <= ST_TAIL;
                            end
                            else begin
                                read_pair_addr <= start_pair_addr;
                                state          <= ST_MEM_REQ;
                            end
                        end
                        else begin
                            header_idx <= header_idx + 1'b1;
                        end
                    end
                end

                ST_MEM_REQ: begin
                    mem_rd_addr <= read_pair_addr;
                    mem_rd_en   <= 1'b1;
                    state       <= ST_MEM_WAIT;
                end

                ST_MEM_WAIT: begin
                    state <= ST_SAMPLE0_HI;
                end

                // data0高字节
                ST_SAMPLE0_HI: begin
                    if (!i_fifo_full)
                        state <= ST_SAMPLE0_LO;
                end

                // data0低字节；到这里才算完整发送1个16bit样点
                ST_SAMPLE0_LO: begin
                    if (!i_fifo_full) begin
                        if ((samples_sent + 1'b1) >= cap_samples_latched) begin
                            samples_sent <= samples_sent + 1'b1;
                            tail_idx     <= 1'b0;
                            state        <= ST_TAIL;
                        end
                        else begin
                            samples_sent <= samples_sent + 1'b1;
                            state        <= ST_SAMPLE1_HI;
                        end
                    end
                end

                ST_SAMPLE1_HI: begin
                    if (!i_fifo_full)
                        state <= ST_SAMPLE1_LO;
                end

                // data1低字节
                ST_SAMPLE1_LO: begin
                    if (!i_fifo_full) begin
                        if ((samples_sent + 1'b1) >= cap_samples_latched) begin
                            samples_sent <= samples_sent + 1'b1;
                            tail_idx     <= 1'b0;
                            state        <= ST_TAIL;
                        end
                        else begin
                            samples_sent   <= samples_sent + 1'b1;
                            read_pair_addr <= read_pair_addr + 1'b1;
                            state          <= ST_MEM_REQ;
                        end
                    end
                end

                // 2Byte正式尾：0A A0
                ST_TAIL: begin
                    if (!i_fifo_full) begin
                        if (!tail_idx) begin
                            tail_idx <= 1'b1;
                        end
                        else begin
                            tail_idx <= 1'b0;
                            dead_cnt <= 32'd0;
                            o_done<=1;
                            state    <= ST_DEAD;
                        end
                    end
                end

                ST_DEAD: begin
                    if (DEAD_CYCLES == 0) begin
                        dead_cnt <= 32'd0;
                        state    <= ST_IDLE;
                    end
                    else if (dead_cnt >= (DEAD_CYCLES - 1'b1)) begin
                        dead_cnt <= 32'd0;
                        state    <= ST_IDLE;
                    end
                    else begin
                        dead_cnt <= dead_cnt + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // 兼容旧顶层参数/端口
    wire unused_channel_id = ^CHANNEL_ID;
    wire unused_cap_num_p  = (CAP_NUM_P != 0);
    wire unused_time_cnt   = ^i_time_cnt;

endmodule

`default_nettype wire
