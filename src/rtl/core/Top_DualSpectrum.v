`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Top_DualSpectrum_v3：双能谱打包模块
//
// 输出格式（总长 = 4*BIN_COUNT + 10 Byte）：
//   Byte 0      : 5A
//   Byte 1      : A5
//   Byte 2      : 0C
//   Byte 3      : packet_length[15:8]
//   Byte 4      : packet_length[7:0]
//   Byte 5      : bin_count[15:8]
//   Byte 6      : bin_count[7:0]
//   Byte 7      : 91=Neutron, 90=Gamma
// Byte 8起：每道32位计数，大端发送
//   Last-1      : 0A
//   Last        : A0
//
// 常用包长：
//   1024 -> 4106  = 0x100A
//   2048 -> 8202  = 0x200A
//   4096 -> 16394 = 0x400A
//   8192 -> 32778 = 0x800A
//
// 处理规则：
// 两套能谱独立累计；
// 复位后先发中子谱，再发伽马谱；
// 90/91放在包内Byte7；
// 包尾标志与最后一个A0同拍；
//   - 彻底移除固定 16516Byte 的协议依赖；
// CMD24道数安全跨到SYS_clk并返回；
// 累计、读出和包头共用同一配置。
// ============================================================================
module Top_DualSpectrum #(
    parameter OUTPUT_SELECT = 1'b1,
    parameter [13:0] DEFAULT_BINS = 14'd4096,
    parameter integer FIFO_READS_LSB_FIRST = 0,
        // 1：CMD24切档时清累计谱
    // 0：CMD24只改变输出rebin，保留累计谱
    parameter CLEAR_ACCUM_ON_BIN_CHANGE = 1'b1
)(
    input  wire        SYS_clk,  // 系统时钟
    input  wire        SYS_rst,  // 系统复位
    input  wire        CLK_200M,  // 二百兆时钟
    input  wire        RST,  // 复位信号

    input  wire [15:0] i_event_peak,  // 事件峰值
    input  wire        i_class_valid,  // 分类结果有效
    input  wire        i_particle_type,  // 粒子类型

    input  wire [31:0] i_timecount,  // 时间戳
    input  wire        i_cmd_control,  // 命令控制字
    input  wire        i_instr_done,  // 指令完成
    input  wire [15:0] i_spectrumperiod,  // 能谱采集周期
    input  wire        i_spec_mode_sys,  // 能谱输出模式

    // CMD24来自200MHz命令域
    input  wire [13:0] i_spectrum_bins_200m,  // 能谱道数
    input  wire        i_spectrum_bins_valid_200m,  // 道数配置有效

    // 调度器每次请求一个字节
    input  wire        i_rd_en,  // 读使能

    output reg         o_empty,  // 空标志
    output reg  [7:0]  o_dout,  // 输出数据
    output reg         o_valid,  // 数据有效
    output reg         o_packet_last,  // 包尾标志
    output wire [31:0] o_rdcnt,  // 待读字节数

    output wire        o_gamma_event_en,  // 伽马事件有效
    output wire        o_neutron_event_en,  // 中子事件有效

    output wire [11:0] o_gamma_dbg_state,  // 调试状态
    output wire [13:0] o_gamma_dbg_tmp_addr,  // 调试暂存地址
    output wire [31:0] o_gamma_dbg_tmp_dataout,  // 调试累计值

    output wire [11:0] o_neutron_dbg_state,  // 调试状态
    output wire [13:0] o_neutron_dbg_tmp_addr,  // 调试暂存地址
    output wire [31:0] o_neutron_dbg_tmp_dataout,  // 调试累计值

    // 200MHz调试/调度信息
    output wire        o_active_select,       // 当前能谱类型
    output wire [15:0] o_packet_byte_count,   // 已发字节数
    output wire [15:0] o_read_issue_count,    // 已请求字节数
    output wire [2:0]  o_mux_state,  // 输出选择状态
    output wire        o_gamma_output_enable,  // 伽马输出使能
    output wire        o_neutron_output_enable,  // 中子输出使能
    output wire [15:0] o_packet_length_dbg,  // 调试包长
    output wire [13:0] o_bins_sys_dbg,  // 调试有效道数

    // FIFO 调试
    output wire        o_gamma_empty,  // 伽马数据为空
    output wire [31:0] o_gamma_rdcnt,  // 伽马剩余字节
    output wire        o_neutron_empty,  // 中子数据为空
    output wire [31:0] o_neutron_rdcnt,  // 中子剩余字节
    output wire        o_gamma_rd_en,  // 伽马读取使能
    output wire        o_neutron_rd_en  // 中子读取使能
    );

    function [13:0] sanitize_bins14;
        input [13:0] bins;  // 有效道数
        begin
            case (bins)
                14'd1024: sanitize_bins14 = 14'd1024;
                14'd2048: sanitize_bins14 = 14'd2048;
                14'd4096: sanitize_bins14 = 14'd4096;
                14'd8192: sanitize_bins14 = 14'd8192;
                default : sanitize_bins14 = DEFAULT_BINS;
            endcase
        end
    endfunction

    function [15:0] calc_packet_length;
        input [13:0] bins;  // 有效道数
        reg [15:0] bins16;
        begin
            bins16 = {2'b00, bins};
            calc_packet_length = (bins16 << 2) + 16'd10;
        end
    endfunction

    // ========================================================================
    // CMD24从200MHz跨到SYS_clk
    // ========================================================================
    reg [13:0] bins_hold_200m;
    reg        bins_toggle_200m;

    always @(posedge CLK_200M or posedge RST) begin
        if (RST) begin
            bins_hold_200m   <= DEFAULT_BINS;
            bins_toggle_200m <= 1'b0;
        end
        else if (i_spectrum_bins_valid_200m) begin
            bins_hold_200m   <= sanitize_bins14(i_spectrum_bins_200m);
            bins_toggle_200m <= ~bins_toggle_200m;
        end
    end

    (* ASYNC_REG="TRUE" *) reg [13:0] bins_bus_s1_sys;
    (* ASYNC_REG="TRUE" *) reg [13:0] bins_bus_s2_sys;
    (* ASYNC_REG = "TRUE" *) reg [2:0] bins_tgl_sync_sys;
    reg        bins_tgl_seen_sys;

    reg [13:0] bins_sys;
    reg [13:0] bins_pending_sys;
    reg        bins_pending_valid_sys;
    reg        bins_apply_pulse_sys;
// ============================================================
// CMD24累计谱清零策略
// 以后需求改变，只需修改参数，不再改内部逻辑
// ============================================================
wire bins_accum_clear_sys =CLEAR_ACCUM_ON_BIN_CHANGE ?bins_apply_pulse_sys :1'b0;
    // CMD24只在暂停时生效。
    // 运行时收到CMD24先暂存，暂停后切换。
    // 切换时只清读出缓存，不清累计RAM。
    always @(posedge SYS_clk or negedge SYS_rst) begin
        if (!SYS_rst) begin
            bins_bus_s1_sys          <= DEFAULT_BINS;
            bins_bus_s2_sys          <= DEFAULT_BINS;
            bins_tgl_sync_sys        <= 3'b000;
            bins_tgl_seen_sys        <= 1'b0;
            bins_sys                 <= DEFAULT_BINS;
            bins_pending_sys         <= DEFAULT_BINS;
            bins_pending_valid_sys   <= 1'b0;
            bins_apply_pulse_sys     <= 1'b0;
        end
        else if (RST) begin
            bins_bus_s1_sys          <= DEFAULT_BINS;
            bins_bus_s2_sys          <= DEFAULT_BINS;
            bins_tgl_sync_sys        <= 3'b000;
            bins_tgl_seen_sys        <= 1'b0;
            bins_sys                 <= DEFAULT_BINS;
            bins_pending_sys         <= DEFAULT_BINS;
            bins_pending_valid_sys   <= 1'b0;
            bins_apply_pulse_sys     <= 1'b0;
        end
        else begin
            bins_bus_s1_sys   <= bins_hold_200m;
            bins_bus_s2_sys   <= bins_bus_s1_sys;
            bins_tgl_sync_sys <= {bins_tgl_sync_sys[1:0], bins_toggle_200m};

            bins_apply_pulse_sys <= 1'b0;

            if (bins_tgl_sync_sys[2] != bins_tgl_seen_sys) begin
                bins_tgl_seen_sys <= bins_tgl_sync_sys[2];

                if (!i_cmd_control) begin
                    // 暂停时直接应用新CMD24。
                    bins_sys               <= sanitize_bins14(bins_bus_s2_sys);
                    bins_pending_sys       <= sanitize_bins14(bins_bus_s2_sys);
                    bins_pending_valid_sys <= 1'b0;
                    bins_apply_pulse_sys   <= 1'b1;
                end
                else begin
                    // 运行时暂存CMD24，等待暂停。
                    bins_pending_sys       <= sanitize_bins14(bins_bus_s2_sys);
                    bins_pending_valid_sys <= 1'b1;
                end
            end
            else if (!i_cmd_control && bins_pending_valid_sys) begin
                // 无新命令时应用暂存的CMD24。
                bins_sys               <= bins_pending_sys;
                bins_pending_valid_sys <= 1'b0;
                bins_apply_pulse_sys   <= 1'b1;
            end
        end
    end

    // 同一配置回到200MHz决定包长。
    reg [13:0] bins_sys_s1_200m;
    reg [13:0] bins_sys_s2_200m;
    always @(posedge CLK_200M or posedge RST) begin
        if (RST) begin
            bins_sys_s1_200m <= DEFAULT_BINS;
            bins_sys_s2_200m <= DEFAULT_BINS;
        end
        else begin
            bins_sys_s1_200m <= bins_sys;
            bins_sys_s2_200m <= bins_sys_s1_200m;
        end
    end

    assign o_bins_sys_dbg = bins_sys;

    // ========================================================================
    // 2. 粒子事件互斥分流
    // ========================================================================
    assign o_gamma_event_en   = i_class_valid && (i_particle_type == 1'b0);
    assign o_neutron_event_en = i_class_valid && (i_particle_type == 1'b1);

    // ========================================================================
    // 上传通道选择同步到SYS_clk。
    // ========================================================================
    reg active_select;
    (* ASYNC_REG = "TRUE" *) reg [1:0] active_select_sync_sys;

    always @(posedge SYS_clk or negedge SYS_rst) begin
        if (!SYS_rst)
            active_select_sync_sys <= {2{OUTPUT_SELECT}};
        else if (RST)
            active_select_sync_sys <= {2{OUTPUT_SELECT}};
        else
            active_select_sync_sys <= {active_select_sync_sys[0], active_select};
    end

    wire active_select_sys = active_select_sync_sys[1];

    assign o_gamma_output_enable =
        i_spec_mode_sys && (active_select_sys == 1'b0);

    assign o_neutron_output_enable =
        i_spec_mode_sys && (active_select_sys == 1'b1);

    // ========================================================================
    // 4. Gamma / Neutron 两套独立能谱
    // ========================================================================
    wire [7:0]  gamma_dout;
    wire        gamma_empty;
    wire        gamma_valid;
    wire        gamma_spectrum_ren;
    wire [31:0] gamma_rdcnt;
    wire        gamma_rd_en;

    wire [13:0] gamma_dbg_addr_unused;
    wire [3:0]  gamma_dbg_count_unused;
    wire        gamma_dbg_flag_instr_unused;
    wire [15:0] gamma_dbg_raw_data;
wire        gamma_dbg_raw_en;
wire [13:0] gamma_dbg_raw_addr;
wire [3:0]  gamma_dbg_reader_state;
 // 调试信号，用于排查8192道
 wire        gamma_dbg_raw_fifo_full;
  wire        gamma_dbg_raw_done;
    Top_spectrum #(
        .FIFO_READS_LSB_FIRST(FIFO_READS_LSB_FIRST)
    ) gamma (
        .SYS_clk                  (SYS_clk),
        .SYS_rst                  (SYS_rst),
        .CLK_200M                 (CLK_200M),
         // 真正的系统复位
       .RST            (RST),
       // 每次CMD24真正apply，都重启发送侧
       .i_output_flush (bins_apply_pulse_sys),
       // 是否同时清累计谱，由参数决定
        .i_accum_clear  (bins_accum_clear_sys),
        .data_AorB_r              (8'd1),
        .voltage_range            (1'b0),
        .output_multiply          (32'h3F800000),
        .timecount                (i_timecount),
        .datain                   (i_event_peak),
        .datain_en                (o_gamma_event_en),
        .cmd_control              (i_cmd_control),
        .i_output_enable          (o_gamma_output_enable),
        .instr_done               (i_instr_done),
        .cmd_spectrumperiod       (i_spectrumperiod),
        .i_spectrum_bins_sys      (bins_sys),
        .SpectrumData_rden        (gamma_rd_en),
        .key_cap_rst              (1'b0),
        .SpectrumData_empty       (gamma_empty),
        .spectrum_ren             (gamma_spectrum_ren),
        .SpectrumData_out         (gamma_dout),
        .SpectrumData_valid       (gamma_valid),
        .spec_rdcnt               (gamma_rdcnt),
        .o_dbg_state              (o_gamma_dbg_state),
        .o_dbg_addr               (gamma_dbg_addr_unused),
        .o_dbg_tmp_addr           (o_gamma_dbg_tmp_addr),
        .o_dbg_tmp_dataout        (o_gamma_dbg_tmp_dataout),
        .o_dbg_count              (gamma_dbg_count_unused),
        .o_dbg_flag_instr         (gamma_dbg_flag_instr_unused),
    .o_dbg_raw_dataout        (gamma_dbg_raw_data),
.o_dbg_raw_dataouten      (gamma_dbg_raw_en),
.o_dbg_raw_addr           (gamma_dbg_raw_addr),
.o_dbg_reader_state       (gamma_dbg_reader_state),

// DEBUG ONLY
.o_dbg_raw_fifo_full      (gamma_dbg_raw_fifo_full),
.o_dbg_raw_done_pulse     (gamma_dbg_raw_done)
    );

    wire [7:0]  neutron_dout;
    wire        neutron_empty;
    wire        neutron_valid;
    wire        neutron_spectrum_ren;
    wire [31:0] neutron_rdcnt;
    wire        neutron_rd_en;

    wire [13:0] neutron_dbg_addr_unused;
    wire [3:0]  neutron_dbg_count_unused;
    wire        neutron_dbg_flag_instr_unused;
  wire [15:0] neutron_dbg_raw_data;
wire        neutron_dbg_raw_en;
wire [13:0] neutron_dbg_raw_addr;
wire [3:0]  neutron_dbg_reader_state;

wire        neutron_dbg_raw_fifo_full;
wire        neutron_dbg_raw_done;

    Top_spectrum #(
        .FIFO_READS_LSB_FIRST(FIFO_READS_LSB_FIRST)
    ) neutron (
        .SYS_clk                  (SYS_clk),
        .SYS_rst                  (SYS_rst),
        .CLK_200M                 (CLK_200M),
       .RST            (RST),
        .i_output_flush (bins_apply_pulse_sys),
        .i_accum_clear  (bins_accum_clear_sys),
        .data_AorB_r              (8'd1),
        .voltage_range            (1'b0),
        .output_multiply          (32'h3F800000),
        .timecount                (i_timecount),
        .datain                   (i_event_peak),
        .datain_en                (o_neutron_event_en),
        .cmd_control              (i_cmd_control),
        .i_output_enable          (o_neutron_output_enable),
        .instr_done               (i_instr_done),
        .cmd_spectrumperiod       (i_spectrumperiod),
        .i_spectrum_bins_sys      (bins_sys),
        .SpectrumData_rden        (neutron_rd_en),
        .key_cap_rst              (1'b0),
        .SpectrumData_empty       (neutron_empty),
        .spectrum_ren             (neutron_spectrum_ren),
        .SpectrumData_out         (neutron_dout),
        .SpectrumData_valid       (neutron_valid),
        .spec_rdcnt               (neutron_rdcnt),
        .o_dbg_state              (o_neutron_dbg_state),
        .o_dbg_addr               (neutron_dbg_addr_unused),
        .o_dbg_tmp_addr           (o_neutron_dbg_tmp_addr),
        .o_dbg_tmp_dataout        (o_neutron_dbg_tmp_dataout),
        .o_dbg_count              (neutron_dbg_count_unused),
        .o_dbg_flag_instr         (neutron_dbg_flag_instr_unused),
        .o_dbg_raw_dataout        (neutron_dbg_raw_data),
.o_dbg_raw_dataouten      (neutron_dbg_raw_en),
.o_dbg_raw_addr           (neutron_dbg_raw_addr),
.o_dbg_reader_state       (neutron_dbg_reader_state),

// DEBUG ONLY
.o_dbg_raw_fifo_full      (neutron_dbg_raw_fifo_full),
.o_dbg_raw_done_pulse     (neutron_dbg_raw_done)
);
    wire [7:0]  selected_dout  = (active_select == 1'b0) ? gamma_dout  : neutron_dout;
    wire        selected_empty = (active_select == 1'b0) ? gamma_empty : neutron_empty;
    wire        selected_valid = (active_select == 1'b0) ? gamma_valid : neutron_valid;
    wire [31:0] selected_rdcnt = (active_select == 1'b0) ? gamma_rdcnt : neutron_rdcnt;

    // ========================================================================
    // 最终数据包生成，工作在200MHz
    // ========================================================================
    localparam [2:0]
        M_WAIT   = 3'd0,
        M_HEADER = 3'd1,
        M_DATA   = 3'd2,
        M_TAIL   = 3'd3;

    reg [2:0]  mux_state;
    reg [2:0]  header_index;
    reg        tail_index;
    reg [15:0] packet_byte_count;
    reg [15:0] read_issue_count;
    reg [15:0] raw_valid_count;
    reg [15:0] raw_bytes_target;
    reg [15:0] packet_length_latched;
    reg [15:0] packet_bins_latched;
    reg        packet_particle;

    assign o_mux_state          = mux_state;
    assign o_packet_byte_count  = packet_byte_count;
    assign o_read_issue_count   = read_issue_count;
    assign o_packet_length_dbg  = packet_length_latched;
    assign o_active_select      = (mux_state == M_WAIT) ? active_select : packet_particle;
    assign o_rdcnt              = selected_rdcnt;

    function [7:0] header_byte;
        input [2:0] idx;  // 循环索引
        input [15:0] packet_len;  // 数据包长度
        input [15:0] bins;  // 有效道数
        input particle;  // 粒子类型
        begin
            case (idx)
                3'd0: header_byte = 8'h5A;
                3'd1: header_byte = 8'hA5;
                3'd2: header_byte = 8'h0C;
                3'd3: header_byte = packet_len[15:8];
                3'd4: header_byte = packet_len[7:0];
                3'd5: header_byte = bins[15:8];
                3'd6: header_byte = bins[7:0];
                3'd7: header_byte = particle ? 8'h91 : 8'h90;
                default: header_byte = 8'h00;
            endcase
        end
    endfunction

    wire selected_fifo_rd_en =
        (mux_state == M_DATA) &&
        i_rd_en &&
        !selected_empty &&
        (read_issue_count < raw_bytes_target);

    assign gamma_rd_en   = selected_fifo_rd_en && (active_select == 1'b0);
    assign neutron_rd_en = selected_fifo_rd_en && (active_select == 1'b1);

    // 包头包尾立即返回，数据跟随FIFO。
    always @(*) begin
        o_empty       = 1'b1;
        o_dout        = 8'h00;
        o_valid       = 1'b0;
        o_packet_last = 1'b0;

        case (mux_state)
            M_WAIT: begin
                o_empty = RST || selected_empty;
                o_dout  = 8'h5A;
                o_valid = i_rd_en && !RST && !selected_empty;
            end

            M_HEADER: begin
                o_empty = 1'b0;
                o_dout  = header_byte(
                            header_index,
                            packet_length_latched,
                            packet_bins_latched,
                            packet_particle
                          );
                o_valid = i_rd_en;
            end

            M_DATA: begin
                o_empty = selected_empty;
                o_dout  = selected_dout;
                o_valid = selected_valid;
            end

            M_TAIL: begin
                o_empty = 1'b0;
                o_dout  = tail_index ? 8'hA0 : 8'h0A;
                o_valid = i_rd_en;
                o_packet_last = i_rd_en && tail_index;
            end

            default: begin
                o_empty = 1'b1;
            end
        endcase
    end

    always @(posedge CLK_200M or posedge RST) begin
        if (RST) begin
            active_select          <= OUTPUT_SELECT;
            mux_state              <= M_WAIT;
            header_index           <= 3'd1;
            tail_index             <= 1'b0;
            packet_byte_count      <= 16'd0;
            read_issue_count       <= 16'd0;
            raw_valid_count        <= 16'd0;
            raw_bytes_target       <= 16'd0;
            packet_length_latched  <= calc_packet_length(DEFAULT_BINS);
            packet_bins_latched    <= {2'b00, DEFAULT_BINS};
            packet_particle        <= OUTPUT_SELECT;
        end
        else begin
            case (mux_state)
                // 收到首个原始字节后再发包头。
                M_WAIT: begin
                    packet_byte_count <= 16'd0;
                    read_issue_count  <= 16'd0;
                    raw_valid_count   <= 16'd0;
                    tail_index        <= 1'b0;

                    if (i_rd_en && !selected_empty) begin
                        packet_bins_latched   <= {2'b00, sanitize_bins14(bins_sys_s2_200m)};
                        packet_length_latched <= calc_packet_length(sanitize_bins14(bins_sys_s2_200m));
                        raw_bytes_target      <= ({2'b00, sanitize_bins14(bins_sys_s2_200m)} << 2);
                        packet_particle       <= active_select;

                        // Byte0=5A 已经在当前拍交给scheduler
                        packet_byte_count <= 16'd1;
                        header_index      <= 3'd1;
                        mux_state         <= M_HEADER;
                    end
                end

                M_HEADER: begin
                    if (i_rd_en) begin
                        packet_byte_count <= packet_byte_count + 1'b1;

                        if (header_index == 3'd7) begin
                            header_index      <= 3'd1;
                            read_issue_count  <= 16'd0;
                            raw_valid_count   <= 16'd0;
                            mux_state         <= M_DATA;
                        end
                        else begin
                            header_index <= header_index + 1'b1;
                        end
                    end
                end

                M_DATA: begin
                    if (selected_fifo_rd_en)
                        read_issue_count <= read_issue_count + 1'b1;

                    // 只在FIFO数据有效时推进计数。
                    if (selected_valid) begin
                        packet_byte_count <= packet_byte_count + 1'b1;

                        if (raw_valid_count == (raw_bytes_target - 1'b1)) begin
                            raw_valid_count <= 16'd0;
                            tail_index      <= 1'b0;
                            mux_state       <= M_TAIL;
                        end
                        else begin
                            raw_valid_count <= raw_valid_count + 1'b1;
                        end
                    end
                end

                M_TAIL: begin
                    if (i_rd_en) begin
                        if (!tail_index) begin
                            // 0A
                            packet_byte_count <= packet_byte_count + 1'b1;
                            tail_index        <= 1'b1;
                        end
                        else begin
                            // A0已送入调度器缓存。
                            // TCP接收包尾后再切换阶段。
                            active_select     <= ~active_select;
                            mux_state         <= M_WAIT;
                            tail_index        <= 1'b0;
                            packet_byte_count <= 16'd0;
                            read_issue_count  <= 16'd0;
                            raw_valid_count   <= 16'd0;
                        end
                    end
                end

                default: begin
                    active_select     <= OUTPUT_SELECT;
                    mux_state         <= M_WAIT;
                    packet_byte_count <= 16'd0;
                    read_issue_count  <= 16'd0;
                    raw_valid_count   <= 16'd0;
                end
            endcase
        end
    end

    assign o_gamma_empty   = gamma_empty;
    assign o_gamma_rdcnt   = gamma_rdcnt;
    assign o_neutron_empty = neutron_empty;
    assign o_neutron_rdcnt = neutron_rdcnt;
    assign o_gamma_rd_en   = gamma_rd_en;
    assign o_neutron_rd_en = neutron_rd_en;
// ========================================================================
// ILA观察能谱读出和FIFO写入
// 只排查8192道卡死，不参与控制
// Clock domain = SYS_clk (= glblclk at top level)
// ========================================================================
ila_spec_writer_sys ila_spec_writer_sys_inst (
    .clk    (SYS_clk),

    // CMD24 / overall control
    .probe0 (bins_sys),                    // 14
    .probe1 (bins_apply_pulse_sys),        // 1
    .probe2 (i_cmd_control),               // 1
    .probe3 (i_spec_mode_sys),             // 1
    .probe4 (active_select_sys),            // 1
    .probe5 (o_gamma_output_enable),        // 1
    .probe6 (o_neutron_output_enable),      // 1

    // Gamma raw reader
    .probe7 (gamma_dbg_reader_state),       // 4
    .probe8 (gamma_dbg_raw_addr),           // 14
    .probe9 (gamma_dbg_raw_en),             // 1
    .probe10(gamma_dbg_raw_fifo_full),      // 1
    .probe11(gamma_dbg_raw_done),           // 1
    .probe12(gamma_spectrum_ren),           // 1 = waiting/delay

    // Neutron raw reader
    .probe13(neutron_dbg_reader_state),     // 4
    .probe14(neutron_dbg_raw_addr),         // 14
    .probe15(neutron_dbg_raw_en),           // 1
    .probe16(neutron_dbg_raw_fifo_full),    // 1
    .probe17(neutron_dbg_raw_done),         // 1
    .probe18(neutron_spectrum_ren)          // 1 = waiting/delay
);
endmodule

`default_nettype wire
