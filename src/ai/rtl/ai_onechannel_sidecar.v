`timescale 1ns/1ps
`default_nettype none

//==============================================================================
//  ai_onechannel_sidecar   
//------------------------------------------------------------------------------
//  单通道 AI 支路；EVENT_CONTROL=1 时由共同事件触发，结果参与最终门控。
//
//  时钟域划分
//    ADC 域 : 触发判决、环形缓存写入、帧提交
//    AI  域 : 帧读取、基线计算、CNN 推理、判决、RBCP 寄存器
//
//  模块间只通过三种方式交互
//    1) ready/ack 双 toggle 握手机制（帧级）
//    2) 双时钟 BRAM 搬运波形与元数据（数据级）
//    3) XPM 格雷码 CDC 搬运统计计数（计数值）
//
//  SAMPLE_STRIDE=5: 1281 raw samples at 2 ns, 257 CNN samples at 10 ns.
//  Centered five-point integer mean, endpoint replication, floor(sum/5).
//  SAMPLE_STRIDE=1 is retained only for the legacy core regression.
//  Ring: RAW_PAIRS sample pairs, followed by four metadata words.
//==============================================================================
module ai_onechannel_sidecar #(parameter EVENT_CONTROL=0,parameter PRE_TRIGGER_PAIRS=60,parameter SAMPLE_STRIDE=5,parameter SATURATION_VETO=0) (
    input wire event_trigger,
    input wire signed [31:0] config_threshold,
    input wire [31:0] gate_busy_count,
    output wire capture_ready,
    output wire [31:0] result_event_id,
    input  wire               adc_clk,
    input  wire               ai_clk,
    input  wire               rst_n,

    input  wire               run_enable,
    input  wire               baseline_valid,
    input  wire [15:0]        baseline,
    input  wire [15:0]        threshold,
    input  wire [15:0]        data0,
    input  wire [15:0]        data1,
    input  wire               data_valid,
    input  wire [47:0]        time_count,

    // RBCP 主机接口（独立地址区间，与既有 TCP 报文互不影响）
    input  wire               rbcp_we,
    input  wire               rbcp_re,
    input  wire [31:0]        rbcp_addr,
    input  wire [7:0]         rbcp_wd,
    output reg                rbcp_ack,
    output reg  [7:0]         rbcp_rd,

    // 推理结果
    output wire               result_valid,
    output wire signed [31:0] result_score,
    output wire               result_candidate
);

//==============================================================================
//  1. 复位同步：两个时钟域各自独立释放
//==============================================================================
    wire adc_rst_n,ai_rst_n;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) adc_reset(.src_arst(rst_n),.dest_clk(adc_clk),.dest_arst(adc_rst_n));
    xpm_cdc_async_rst #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) ai_reset(.src_arst(rst_n),.dest_clk(ai_clk),.dest_arst(ai_rst_n));

//==============================================================================
//  2. 跨时钟控制：enable / ready / ack 三组握手
//------------------------------------------------------------------------------
//  ready_toggle 在 ADC 域每提交一帧翻转一次，
//  ack_toggle   在 AI  域每消费完一帧翻转一次，
//  二者相等即表示邮箱空闲（mailbox_free）。
//==============================================================================
    reg               ai_enable;            // 常驻 AI 域，1 = 允许采集与推理
    reg signed [31:0] decision_threshold;

    (* ASYNC_REG = "TRUE" *) reg [1:0] enable_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ready_sync;

    reg ready_toggle;                       // ADC 域：一帧写完翻转
    reg ack_toggle;                         // AI  域：一帧读完翻转

    // ADC 域采样 AI 域的控制量
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            enable_sync <= 2'b00;
            ack_sync    <= 2'b00;
        end else begin
            enable_sync <= {enable_sync[0], ai_enable};
            ack_sync    <= {ack_sync[0],    ack_toggle};
        end
    end

    // AI 域采样 ADC 域的 ready 标志
    always @(posedge ai_clk or negedge ai_rst_n) begin
        if (!ai_rst_n) ready_sync <= 2'b00;
        else           ready_sync <= {ready_sync[0], ready_toggle};
    end

//==============================================================================
//  3. 触发判决（ADC 域）
//------------------------------------------------------------------------------
//  比较前做 17 位无符号扩展，避免 16 位加法溢出。
//  上升沿由 previous_above 记录，严格按边沿触发。
//==============================================================================
    wire [16:0] trigger_level = {1'b0, baseline} + {1'b0, threshold};

    wire above = baseline_valid &&
                 (({1'b0, data0} > trigger_level) || ({1'b0, data1} > trigger_level));

    reg previous_above; // Declared before use for Vivado 2022.1.
    wire automatic_trigger = data_valid && run_enable && enable_sync[1] && above && !previous_above;

//==============================================================================
//  4. 采集存储与写侧状态机（ADC 域）
//------------------------------------------------------------------------------
//  邮箱语义：写侧必须等到完整一帧被读侧消费完才能写下一帧。
//  每个 ADC 时钟写 32 位，每个 AI 时钟同步读 32 位。
//
//  注意：真正的双时钟 BRAM 推断要求唯一的写端口，
//        因此 4 个元数据字也复用它，按 commit_stage 分时写入。
//==============================================================================
    localparam integer RAW_SAMPLES = 256*SAMPLE_STRIDE+1;
    localparam integer RAW_PAIRS = (RAW_SAMPLES+1)/2;
    localparam integer ADDR_W = $clog2(RAW_PAIRS+4);
    localparam integer PRIME_W = $clog2(PRE_TRIGGER_PAIRS+1);
    (* ram_style = "block" *) reg [31:0] capture_ram [0:RAW_PAIRS+3];

    reg [ADDR_W-1:0] write_ptr;
    reg [ADDR_W-1:0] frame_start_adc;
    reg [ADDR_W-1:0] post_remaining;              // 触发后还需采集的样本对数
    reg [PRIME_W-1:0] prime_pairs;                 // 环形缓存已预填的样本对数
    reg        capturing;
    reg [2:0]  commit_stage;                // 0 = 空闲，1..4 = 元数据提交流水
    reg [31:0] capture_count_adc;
    reg [31:0] busy_edges_adc;
    reg [31:0] frame_seq_adc;
    reg [47:0] frame_time_adc;

    wire mailbox_free = (ready_toggle == ack_sync[1]);

    wire trigger_edge = EVENT_CONTROL ? (event_trigger && run_enable && enable_sync[1]) : automatic_trigger;
    assign capture_ready = mailbox_free && prime_pairs==PRE_TRIGGER_PAIRS && !capturing && commit_stage==0 && enable_sync[1] && run_enable && baseline_valid;
    wire ram_write = data_valid && (capturing || mailbox_free) && (commit_stage == 0);

    reg [ADDR_W-1:0] ram_write_addr;
    reg [31:0] ram_write_data;

    always @(*) begin
        ram_write_addr = write_ptr;
        ram_write_data = {data1, data0};

        case (commit_stage)
            3'd1: begin
                ram_write_addr = RAW_PAIRS;
                ram_write_data = {{(32-ADDR_W){1'b0}}, frame_start_adc};
            end
            3'd2: begin
                ram_write_addr = RAW_PAIRS+1;
                ram_write_data = frame_seq_adc;
            end
            3'd3: begin
                ram_write_addr = RAW_PAIRS+2;
                ram_write_data = frame_time_adc[31:0];
            end
            3'd4: begin
                ram_write_addr = RAW_PAIRS+3;
                ram_write_data = {16'b0, frame_time_adc[47:32]};
            end
            default: begin
            end
        endcase
    end

    // 唯一的写端口：波形写入与元数据提交共用
    always @(posedge adc_clk) begin
        if (ram_write || commit_stage != 0)
            capture_ram[ram_write_addr] <= ram_write_data;
    end

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            write_ptr         <= 8'd0;
            frame_start_adc   <= 8'd0;
            post_remaining    <= 8'd0;
            prime_pairs       <= 4'd0;
            capturing         <= 1'b0;
            commit_stage      <= 3'd0;
            previous_above    <= 1'b0;
            ready_toggle      <= 1'b0;
            capture_count_adc <= 32'd0;
            busy_edges_adc    <= 32'd0;
            frame_seq_adc     <= 32'd0;
            frame_time_adc    <= 48'd0;
        end else begin
            // 边沿检测历史
            if (data_valid)
                previous_above <= above;

            // 写指针推进 + 预填计数
            if (ram_write) begin
                write_ptr <= (write_ptr == RAW_PAIRS-1) ? 8'd0 : (write_ptr + 8'd1);
                if (prime_pairs < PRE_TRIGGER_PAIRS)
                    prime_pairs <= prime_pairs + 4'd1;
            end

            // 邮箱被占用时清空预填计数，保证触发时缓存里是连续的新数据
            // 注意：此行优先级高于上面的自增，两者同时成立时结果为清零
            if (!mailbox_free)
                prime_pairs <= 4'd0;

            // 忙时被丢弃的触发沿计数
            if (trigger_edge && (capturing || !mailbox_free || commit_stage != 0))
                busy_edges_adc <= busy_edges_adc + 32'd1;

            // 元数据提交流水线：4 个字写完后翻转 ready_toggle
            if (commit_stage != 0) begin
                if (commit_stage == 3'd4) begin
                    commit_stage <= 3'd0;
                    ready_toggle <= ~ready_toggle;
                end else begin
                    commit_stage <= commit_stage + 3'd1;
                end
            end

            if (!capturing && commit_stage == 0 && mailbox_free &&
                prime_pairs == PRE_TRIGGER_PAIRS && trigger_edge) begin
                // 触发：起始指针回退 8 对，使帧内含触发前历史样本
                frame_start_adc   <= (write_ptr >= PRE_TRIGGER_PAIRS) ? (write_ptr - PRE_TRIGGER_PAIRS)
                                                          : (write_ptr + (RAW_PAIRS-PRE_TRIGGER_PAIRS));
                post_remaining    <= (RAW_PAIRS-1-PRE_TRIGGER_PAIRS);
                capturing         <= 1'b1;
                capture_count_adc <= capture_count_adc + 32'd1;
                frame_seq_adc     <= capture_count_adc + 32'd1;
                frame_time_adc    <= time_count;
            end else if (capturing && data_valid) begin
                if (post_remaining == 8'd1) begin
                    capturing      <= 1'b0;
                    post_remaining <= 8'd0;
                    commit_stage   <= 3'd1;
                end else begin
                    post_remaining <= post_remaining - 8'd1;
                end
            end
        end
    end

//==============================================================================
//  5. 统计计数跨时钟（ADC -> AI）
//------------------------------------------------------------------------------
//  xpm_cdc_gray 在源时钟域内先打拍再转格雷码，
//  因此源端必须接寄存器输出，不能接组合逻辑。
//==============================================================================
    wire [31:0] capture_count_ai;
    wire [31:0] busy_edges_ai;

    xpm_cdc_gray #(
        .DEST_SYNC_FF         (2),
        .INIT_SYNC_FF         (1),
        .REG_OUTPUT           (1),
        .SIM_ASSERT_CHK       (1),
        .SIM_LOSSLESS_GRAY_CHK(0),
        .WIDTH                (32)
    ) capture_count_cdc (
        .src_clk     (adc_clk),
        .src_in_bin  (capture_count_adc),
        .dest_clk    (ai_clk),
        .dest_out_bin(capture_count_ai)
    );

    xpm_cdc_gray #(
        .DEST_SYNC_FF         (2),
        .INIT_SYNC_FF         (1),
        .REG_OUTPUT           (1),
        .SIM_ASSERT_CHK       (1),
        .SIM_LOSSLESS_GRAY_CHK(0),
        .WIDTH                (32)
    ) busy_edges_cdc (
        .src_clk     (adc_clk),
        .src_in_bin  (busy_edges_adc),
        .dest_clk    (ai_clk),
        .dest_out_bin(busy_edges_ai)
    );

    // 忙标志先在 ADC 域打拍，再跨到 AI 域，避免组合路径跨时钟
    reg source_busy_registered;

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) source_busy_registered <= 1'b0;
        else            source_busy_registered <= capturing || (commit_stage != 0);
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] cap_sync;

    always @(posedge ai_clk or negedge ai_rst_n) begin
        if (!ai_rst_n) cap_sync <= 2'b00;
        else           cap_sync <= {cap_sync[0], source_busy_registered};
    end

//==============================================================================
//  6. 读侧状态机（AI 域）
//------------------------------------------------------------------------------
//  每检测到一次 ready_toggle 翻转，完整消费一帧：
//    读元数据 -> 原始帧五点均值降采样 -> 前16个降采样点求基线 -> CNN
//  元数据经双时钟 RAM 搬运，绝不跨时钟直连数据总线。
//==============================================================================
    localparam IDLE=4'd0, META_REQ=4'd1, META_WAIT=4'd2,
               DATA_REQ=4'd3, DATA_WAIT=4'd4, RAW0=4'd5, RAW1=4'd6,
               PAD=4'd7, START_CNN=4'd8, SEND0=4'd9, WAIT_SCORE=4'd10,
               DRAIN=4'd11, CNN_REQ=4'd12;
    reg [3:0] state;
    reg [ADDR_W-1:0] read_ptr,start_ptr_ai;
    reg [1:0] meta_word;
    reg [19:0] baseline_sum;
    reg [31:0] pair_data;
    reg [8:0] sample_index,reduce_index;
    reg [10:0] raw_index;
    reg [2:0] dec_phase;
    reg [15:0] history0,history1,history2,history3,last_raw;
    reg frame_toggle_ai;
    reg [31:0] frame_seq_ai;
    reg [47:0] frame_time_ai;
    reg signed [31:0] frame_threshold;
    reg frame_saturated,last_saturated,last_cnn_candidate;
    reg [31:0] saturated_count,snapshot_saturated_count,snapshot_guard;
    reg mean_valid,reduced_valid;
    reg [18:0] mean_sum_pipe;
    reg [8:0] mean_index_pipe,reduced_index_pipe;
    reg [15:0] reduced_pipe,cnn_sample;
    wire ram_read=(state==DATA_REQ)||(state==META_REQ);
    reg [31:0] ram_q;
    always @(posedge ai_clk) if(ram_read) ram_q<=capture_ram[read_ptr];

    wire reducing=(state==RAW0)||(state==RAW1)||(state==PAD);
    wire [15:0] scan_sample=(state==PAD)?last_raw:
                           ((state==RAW1)?pair_data[31:16]:pair_data[15:0]);
    wire [16:0] sum01={1'b0,scan_sample}+{1'b0,history0};
    wire [16:0] sum23={1'b0,history1}+{1'b0,history2};
    wire [18:0] mean_sum={2'b0,sum01}+{2'b0,sum23}+{3'b0,history3};
    wire emit_reduced=reducing && ((SAMPLE_STRIDE==1)||(dec_phase==3'd2));
    localparam integer LAST_SCAN=(SAMPLE_STRIDE==1)?RAW_SAMPLES-1:RAW_SAMPLES+1;

//==============================================================================
//  7. CNN 推理（AI 域）
//------------------------------------------------------------------------------
//  归一化  x = (raw - mean(first 16)) / 32768
//  定点 <24,10> 直接实现为 floor((16*raw - sum16) / 32)：
//      centered   = 16*raw - sum16     21 bit signed
//      normalized = centered >>> 5     24 bit signed
//==============================================================================
    reg         cnn_start;
    wire        cnn_ready;
    wire        cnn_done;
    wire        cnn_idle;
    wire        cnn_input_ready;
    wire        cnn_output_valid;
    wire [31:0] cnn_output;

    (* ram_style = "distributed" *) reg [15:0] debug_wave [0:256];

    wire cnn_input_valid = (state == SEND0);

    wire [15:0] raw_sample = cnn_sample;

    wire signed [20:0] centered =
        $signed({1'b0, raw_sample, 4'b0}) - $signed({1'b0, baseline_sum});

    wire signed [23:0] normalized =
        $signed({{3{centered[20]}}, centered}) >>> 5;

    wire [31:0] cnn_input = {{8{normalized[23]}}, normalized};

    wire signed [31:0] score = {{8{cnn_output[23]}}, cnn_output[23:0]};

    pulse_cnn cnn_inst (
        .ap_clk             (ai_clk),
        .ap_rst_n           (ai_rst_n),
        .ap_start           (cnn_start),
        .ap_done            (cnn_done),
        .ap_idle            (cnn_idle),
        .ap_ready           (cnn_ready),
        .waveform_TDATA     (cnn_input),
        .waveform_TVALID    (cnn_input_valid),
        .waveform_TREADY    (cnn_input_ready),
        .layer15_out_TDATA  (cnn_output),
        .layer15_out_TVALID (cnn_output_valid),
        .layer15_out_TREADY (1'b1)
    );

//==============================================================================
//  8. 统计、结果输出与调试波形
//==============================================================================
    reg [31:0] processed_count;
    reg [31:0] candidate_count;
    reg [31:0] rejected_count;
    reg [31:0] last_seq;
    reg [47:0] last_time;
    reg signed [31:0] last_score;
    reg        last_candidate;
    reg [19:0] last_baseline_sum;
    reg        result_pulse;


    assign result_event_id = last_seq;
    assign result_valid     = result_pulse;
    assign result_score     = last_score;
    assign result_candidate = last_candidate;

    // A single AI-domain write port: debug readback is exactly the CNN input.
    always @(posedge ai_clk) begin
        if(reduced_valid) debug_wave[reduced_index_pipe]<=reduced_pipe;
        if(state==CNN_REQ) cnn_sample<=debug_wave[sample_index];
    end

    always @(posedge ai_clk or negedge ai_rst_n) begin
        if(!ai_rst_n) begin
            state<=IDLE;read_ptr<=0;start_ptr_ai<=0;meta_word<=0;
            baseline_sum<=0;pair_data<=0;sample_index<=0;reduce_index<=0;
            raw_index<=0;dec_phase<=0;history0<=0;history1<=0;history2<=0;history3<=0;last_raw<=0;
            mean_valid<=0;reduced_valid<=0;mean_sum_pipe<=0;
            mean_index_pipe<=0;reduced_index_pipe<=0;reduced_pipe<=0;
            frame_toggle_ai<=0;frame_seq_ai<=0;frame_time_ai<=0;frame_threshold<=0;
            frame_saturated<=0;last_saturated<=0;last_cnn_candidate<=0;saturated_count<=0;
            ack_toggle<=0;cnn_start<=0;processed_count<=0;candidate_count<=0;rejected_count<=0;
            last_seq<=0;last_time<=0;last_score<=0;last_candidate<=0;last_baseline_sum<=0;result_pulse<=0;
        end else begin
            result_pulse<=0;
            if(reducing && raw_index<RAW_SAMPLES && scan_sample>=16'hfffc)frame_saturated<=1;
            // Separate sum, constant division, and baseline accumulation.
            // Do not put all three on one 200 MHz combinational path.
            mean_valid<=emit_reduced;reduced_valid<=mean_valid;
            if(emit_reduced)begin
                mean_sum_pipe<=(SAMPLE_STRIDE==1)?{3'b0,scan_sample}:mean_sum;
                mean_index_pipe<=reduce_index;
            end
            if(mean_valid)begin
                reduced_pipe<=(SAMPLE_STRIDE==1)?mean_sum_pipe[15:0]:(mean_sum_pipe/19'd5);
                reduced_index_pipe<=mean_index_pipe;
            end
            if(reduced_valid && reduced_index_pipe<16)
                baseline_sum<=baseline_sum+{4'b0,reduced_pipe};
            if(cnn_ready)cnn_start<=0;
            case(state)
                IDLE:if(ready_sync[1]!=ack_toggle)begin
                    read_ptr<=RAW_PAIRS;meta_word<=0;
                    frame_threshold<=EVENT_CONTROL?config_threshold:decision_threshold;
                    frame_toggle_ai<=ready_sync[1];baseline_sum<=0;frame_saturated<=0;
                    sample_index<=0;reduce_index<=0;raw_index<=0;dec_phase<=0;
                    state<=META_REQ;
                end
                META_REQ:state<=META_WAIT;
                META_WAIT:begin
                    case(meta_word)
                        0:start_ptr_ai<=ram_q[ADDR_W-1:0];
                        1:frame_seq_ai<=ram_q;
                        2:frame_time_ai[31:0]<=ram_q;
                        3:frame_time_ai[47:32]<=ram_q[15:0];
                    endcase
                    if(meta_word==3)begin read_ptr<=start_ptr_ai;state<=DATA_REQ;end
                    else begin meta_word<=meta_word+1'b1;read_ptr<=read_ptr+1'b1;state<=META_REQ;end
                end
                DATA_REQ:state<=DATA_WAIT;
                DATA_WAIT:begin pair_data<=ram_q;state<=RAW0;end
                RAW0,RAW1,PAD:begin
                    if(raw_index==0)begin
                        // Left boundary: x[-2]=x[-1]=x[0].
                        history0<=scan_sample;history1<=scan_sample;
                        history2<=scan_sample;history3<=scan_sample;
                    end else begin
                        history0<=scan_sample;history1<=history0;
                        history2<=history1;history3<=history2;
                    end
                    last_raw<=scan_sample;
                    dec_phase<=(dec_phase==4)?0:dec_phase+1'b1;
                    if(emit_reduced)begin
                        reduce_index<=reduce_index+1'b1;
                    end
                    raw_index<=raw_index+1'b1;
                    if(raw_index==LAST_SCAN)begin
                        // Raw RAM can now refill; reduced input is frozen independently.
                        ack_toggle<=frame_toggle_ai;state<=DRAIN;
                    end else if(raw_index>=RAW_SAMPLES-1)state<=PAD;
                    else if(state==RAW0)state<=RAW1;
                    else begin
                        read_ptr<=(read_ptr==RAW_PAIRS-1)?0:read_ptr+1'b1;
                        state<=DATA_REQ;
                    end
                end
                DRAIN:if(reduced_valid && reduced_index_pipe==256)state<=START_CNN;
                START_CNN:begin cnn_start<=1;sample_index<=0;state<=CNN_REQ;end
                CNN_REQ:state<=SEND0;
                SEND0:if(cnn_input_ready)begin
                    if(sample_index==256)state<=WAIT_SCORE;
                    else begin sample_index<=sample_index+1'b1;state<=CNN_REQ;end
                end
                WAIT_SCORE:if(cnn_output_valid)begin
                    last_score<=score;last_cnn_candidate<=score>frame_threshold;last_saturated<=frame_saturated;
                    last_candidate<=(score>frame_threshold) && (!SATURATION_VETO || !frame_saturated);
                    if(frame_saturated)saturated_count<=saturated_count+1'b1;
                    processed_count<=processed_count+1'b1;
                    if((score>frame_threshold) && (!SATURATION_VETO || !frame_saturated))candidate_count<=candidate_count+1'b1;
                    else rejected_count<=rejected_count+1'b1;
                    last_seq<=frame_seq_ai;last_time<=frame_time_ai;
                    last_baseline_sum<=baseline_sum;result_pulse<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end

//==============================================================================
//  9. RBCP 寄存器接口（AI 域）
//------------------------------------------------------------------------------
//  独立地址区间，既有 TCP 报文的内容与字节序均不变。
//    0x100..0x14F  控制/状态寄存器（16 x 32 bit）
//    0x200..0x401  调试波形（256 x 16 bit，字节序选择由 addr[0] 决定）
//
//  寄存器表
//    0x100  只读  ID = "AI13"
//    0x101  只读  ai_enable
//    0x102  只读  decision_threshold
//    0x103  只读  busy
//    0x104  只读  快照命令/状态（恒为 1）
//    0x105..0x10F  只读  snapshot[0..10]
//    0x107  只写  ai_enable
//    0x108..0x10B  只写  decision_threshold[31:0]（高字节在前）
//    0x110  只写  触发统计快照
//==============================================================================
    wire register_selected = (rbcp_addr >= 32'h0000_0100) && (rbcp_addr < 32'h0000_0160);
    wire wave_selected     = (rbcp_addr >= 32'h0000_0200) && (rbcp_addr < 32'h0000_0402);
    wire selected          = register_selected || wave_selected;

    wire [31:0] gate_busy_ai;
    generate if(EVENT_CONTROL)begin : gate_count_enabled
    xpm_cdc_gray #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.REG_OUTPUT(1),.SIM_ASSERT_CHK(1),.WIDTH(32)) gate_counter_cdc
      (.src_clk(adc_clk),.src_in_bin(gate_busy_count),.dest_clk(ai_clk),.dest_out_bin(gate_busy_ai));
    end else begin : gate_count_disabled
      assign gate_busy_ai=0;
    end endgenerate
    wire busy = (state != IDLE) || cap_sync[1] || (ready_sync[1] != ack_toggle);

    reg [31:0] snapshot [0:10];
    reg [31:0] read_word;

    always @(*) begin
        case (rbcp_addr[7:2])
            6'h00:   read_word = 32'h4149_3133;      // "AI13"，基址 0x100
            6'h01:   read_word = {31'b0, ai_enable};
            6'h02:   read_word = EVENT_CONTROL ? config_threshold : decision_threshold;
            6'h03:   read_word = {31'b0, busy};
            6'h04:   read_word = 32'd1;
            6'h05:   read_word = snapshot[0];
            6'h06:   read_word = snapshot[1];
            6'h07:   read_word = snapshot[2];
            6'h08:   read_word = snapshot[3];
            6'h09:   read_word = snapshot[4];
            6'h0A:   read_word = snapshot[5];
            6'h0B:   read_word = snapshot[6];
            6'h0C:   read_word = snapshot[7];
            6'h0D:   read_word = snapshot[8];
            6'h0E:   read_word = snapshot[9];
            6'h0F:   read_word = snapshot[10];
            6'h10: read_word = EVENT_CONTROL ? gate_busy_ai : 0;
            6'h11: read_word = 32'd2*SAMPLE_STRIDE; // 0x144: AI sample spacing in ns
            6'h12: read_word = 32'd257;             // 0x148: CNN sample count
            6'h13: read_word = RAW_SAMPLES;         // 0x14C: raw samples per AI frame
            6'h14: read_word = 32'h2026_1103; // 0x150: new-board binary model revision
            6'h15: read_word = snapshot_guard; // 0x154: bit0 CNN pass, bit1 raw clipping, bit2 veto enabled
            6'h16: read_word = snapshot_saturated_count; // 0x158: raw-saturated frames
            6'h17: read_word = 32'd4043; // 0x15C: trained default threshold Q14
            default: read_word = 32'd0;
        endcase
    end

    wire [8:0]  debug_index = (rbcp_addr - 32'h200) >> 1;
    wire [15:0] debug_value = debug_wave[debug_index];

    integer j;

    always @(posedge ai_clk or negedge ai_rst_n) begin
        if (!ai_rst_n) begin
            ai_enable          <= 1'b1;
            decision_threshold <= 32'sd0;
            rbcp_ack           <= 1'b0;
            rbcp_rd            <= 8'd0;
            snapshot_guard<=0;snapshot_saturated_count<=0;
            for (j = 0; j < 11; j = j + 1)
                snapshot[j] <= 32'd0;
        end else begin
            rbcp_ack <= selected && (rbcp_we || rbcp_re);

            // ---- 读通路 ----
            if (selected && rbcp_re) begin
                if (wave_selected)
                    rbcp_rd <= rbcp_addr[0] ? debug_value[7:0] : debug_value[15:8];
                else begin
                    case (rbcp_addr[1:0])
                        2'd0: rbcp_rd <= read_word[31:24];
                        2'd1: rbcp_rd <= read_word[23:16];
                        2'd2: rbcp_rd <= read_word[15:8];
                        2'd3: rbcp_rd <= read_word[7:0];
                    endcase
                end
            end

            // ---- 写通路 ----
            if (register_selected && rbcp_we) begin
                if (rbcp_addr == 32'h107)
                    ai_enable <= rbcp_wd[0];

                case (rbcp_addr)
                    32'h108: decision_threshold[31:24] <= rbcp_wd;
                    32'h109: decision_threshold[23:16] <= rbcp_wd;
                    32'h10A: decision_threshold[15:8]  <= rbcp_wd;
                    32'h10B: decision_threshold[7:0]   <= rbcp_wd;

                    32'h110: begin
                        snapshot_guard<={29'd0,(SATURATION_VETO!=0),last_saturated,last_cnn_candidate};
                        snapshot_saturated_count<=saturated_count;
                        snapshot[0]  <= processed_count;
                        snapshot[1]  <= candidate_count;
                        snapshot[2]  <= rejected_count;
                        snapshot[3]  <= capture_count_ai;
                        snapshot[4]  <= busy_edges_ai;
                        snapshot[5]  <= last_score;
                        snapshot[6]  <= last_seq;
                        snapshot[7]  <= {16'b0, last_time[47:32]};
                        snapshot[8]  <= last_time[31:0];
                        snapshot[9]  <= {31'b0, last_candidate};
                        snapshot[10] <= {12'b0, last_baseline_sum};
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
