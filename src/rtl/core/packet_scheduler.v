// AD9694 wave/spectrum-only TCP scheduler. No periodic auxiliary packets.
`timescale 1ns / 1ps
`default_nettype none

module packet_scheduler #(parameter CONFIG_INTERLOCK=0, parameter TIMESTAMPED=0, parameter MIXED_STREAM=0) (

    input  wire        clk_200m,
    input  wire        rst_n_200m,
    input  wire        soft_reset_200m,

    input  wire        run_enable_200m,
    input  wire        work_mode_200m,
    input  wire        event_idle_200m,

    input  wire [15:0] wave_sample_points_200m,
    input  wire        wave_sample_points_valid_200m,

    output reg  [15:0] wave_sample_points_active_200m,

    output reg         wave_cfg_apply_pulse_200m,

    input  wire        tcp_tx_full,
    output reg  [7:0]  tcp_tx_data,
    output reg         tcp_tx_wr,

    input  wire [7:0]  wave_dout,
    input  wire        wave_empty,
    input  wire        wave_valid,
    output wire        wave_rd_en,

    input  wire [7:0]  spec_dout,
    input  wire        spec_empty,
    input  wire        spec_valid,
    output wire        spec_rd_en,
    input  wire        spec_packet_last,

    output wire [3:0] dbg_state,
    output wire [15:0] dbg_wave_byte_count,
    output wire dbg_spec_packet_active,
    output wire dbg_source_buf_valid,
    output reg dbg_wave_packet_done_pulse,
    output reg dbg_spec_packet_done_pulse
);
    localparam [3:0] ST_IDLE=4'd0, ST_WAVE=4'd1, ST_SPEC=4'd2;
    reg [3:0] state;
    assign dbg_state = state;
    wire source_state =
        (state == ST_WAVE) ||     (state == ST_SPEC);

    wire source_is_wave = (state == ST_WAVE);

    wire [7:0] source_dout =
        source_is_wave ? wave_dout : spec_dout;

    wire source_empty =
        source_is_wave ? wave_empty : spec_empty;

    wire source_valid =
        source_is_wave ? wave_valid : spec_valid;

    reg       source_buf_valid;
    reg [7:0] source_buf_data;
    reg       source_read_pending;

    reg       source_buf_spec_last;

    assign dbg_source_buf_valid = source_buf_valid;

    function [15:0] sanitize_wave_samples;
        input [15:0] n;
        begin
            if (n > 16'd2047)
                sanitize_wave_samples = 16'd2047;
            else
                sanitize_wave_samples = n;
        end
    endfunction

    reg [15:0] wave_sample_points_pending;
    reg        wave_sample_points_pending_valid;

   wire [15:0] wave_packet_bytes_cfg =
    (wave_sample_points_active_200m << 1) + (TIMESTAMPED ? 16'd15 : 16'd9);

    reg [15:0] wave_packet_bytes_latched;

    reg [15:0] wave_byte_count;
    assign dbg_wave_byte_count = wave_byte_count;

    wire wave_packet_committed =
        (wave_byte_count != 16'd0) ||
        source_buf_valid ||
        source_read_pending;

    reg prefer_spec;
    reg spec_packet_active;
    assign dbg_spec_packet_active = spec_packet_active;

    wire spec_packet_committed =
        spec_packet_active ||
        source_buf_valid ||
        source_read_pending;

    wire wave_can_start_new_packet =
        (run_enable_200m || (CONFIG_INTERLOCK && !event_idle_200m)) &&
        (MIXED_STREAM || work_mode_200m == 1'b0);

    wire spec_can_start_new_packet =
        run_enable_200m &&
        (MIXED_STREAM || work_mode_200m == 1'b1);

    wire source_read_allowed =
        (state == ST_WAVE)
        ? (wave_packet_committed || wave_can_start_new_packet)
        :
        (state == ST_SPEC)
        ? (spec_packet_committed || spec_can_start_new_packet)
        : 1'b0;

    wire source_issue_read =
        rst_n_200m && !soft_reset_200m &&
        source_state &&
        source_read_allowed &&
        !source_buf_valid &&
        !source_read_pending &&
        !source_empty;

    assign wave_rd_en =
        source_issue_read && (state == ST_WAVE);

    assign spec_rd_en =
        source_issue_read && (state == ST_SPEC);

    wire source_tcp_accept =
        rst_n_200m && !soft_reset_200m &&
        source_state &&
        source_buf_valid &&
        !tcp_tx_full;

    always @(posedge clk_200m) begin
        if (!rst_n_200m || soft_reset_200m) begin
            source_buf_valid         <= 1'b0;
            source_buf_data          <= 8'h00;
            source_read_pending      <= 1'b0;
            source_buf_spec_last     <= 1'b0;
        end
        else begin

            if (!source_state) begin
                source_buf_valid         <= 1'b0;
                source_read_pending      <= 1'b0;
                source_buf_spec_last     <= 1'b0;
            end
            else begin
                if (source_issue_read)
                    source_read_pending <= 1'b1;

                if (source_valid &&
                    (source_read_pending || source_issue_read)) begin
                    source_buf_data     <= source_dout;
                    source_buf_valid    <= 1'b1;
                    source_read_pending <= 1'b0;

                    if (state == ST_SPEC) begin
                        source_buf_spec_last     <= spec_packet_last;
                    end
                    else begin
                        source_buf_spec_last     <= 1'b0;
                    end
                end

                if (source_tcp_accept) begin
                    source_buf_valid     <= 1'b0;
                    source_buf_spec_last <= 1'b0;
                end
            end
        end
    end

    // A pending FIFO response is held until TCP accepts it, even if full rises.
    always @(*) begin
        tcp_tx_data = source_buf_data;
        tcp_tx_wr = source_tcp_accept;
    end

    always @(posedge clk_200m) begin
        if (!rst_n_200m || soft_reset_200m) begin
            state <= ST_IDLE;prefer_spec<=0;
            wave_byte_count <= 16'd0;
            wave_packet_bytes_latched <= 16'd521;
            spec_packet_active <= 1'b0;
            wave_sample_points_active_200m <= 16'd256;
            wave_sample_points_pending <= 16'd256;
            wave_sample_points_pending_valid <= 1'b0;
            wave_cfg_apply_pulse_200m <= 1'b0;
            dbg_wave_packet_done_pulse <= 1'b0;
            dbg_spec_packet_done_pulse <= 1'b0;
        end else begin
            wave_cfg_apply_pulse_200m <= 1'b0;
            dbg_wave_packet_done_pulse <= 1'b0;
            dbg_spec_packet_done_pulse <= 1'b0;
            if (wave_sample_points_valid_200m) begin
                wave_sample_points_pending <= sanitize_wave_samples(wave_sample_points_200m);
                wave_sample_points_pending_valid <= 1'b1;
            end
            // CMD23 applies only while paused, after the current packet drains.
            if (!run_enable_200m && state == ST_IDLE &&
                (!CONFIG_INTERLOCK || event_idle_200m) &&
                !source_buf_valid && !source_read_pending &&
                wave_sample_points_pending_valid && !wave_sample_points_valid_200m) begin
                wave_sample_points_active_200m <= wave_sample_points_pending;
                wave_sample_points_pending_valid <= 1'b0;
                wave_cfg_apply_pulse_200m <= 1'b1;
            end
            case (state)
                ST_IDLE: begin
                    wave_byte_count <= 16'd0;
                    spec_packet_active <= 1'b0;
                    if (run_enable_200m || (CONFIG_INTERLOCK && !event_idle_200m)) begin
                        if (MIXED_STREAM && prefer_spec && spec_can_start_new_packet && !spec_empty) begin
                            state <= ST_SPEC;
                        end else if (wave_can_start_new_packet && !wave_empty) begin
                            wave_packet_bytes_latched <= wave_packet_bytes_cfg;
                            state <= ST_WAVE;
                        end else if (spec_can_start_new_packet && (!MIXED_STREAM || !spec_empty)) begin
                            state <= ST_SPEC;
                        end
                    end
                end
                ST_WAVE: begin
                    if (!wave_packet_committed && !wave_can_start_new_packet)
                        state <= ST_IDLE;
                    if (source_tcp_accept) begin
                        if (wave_byte_count == wave_packet_bytes_latched - 1'b1) begin
                            wave_byte_count <= 16'd0;
                            dbg_wave_packet_done_pulse <= 1'b1;
                            if (MIXED_STREAM)begin state<=ST_IDLE;prefer_spec<=1;end
                            else if (wave_can_start_new_packet)
                                wave_packet_bytes_latched <= wave_packet_bytes_cfg;
                            else
                                state <= ST_IDLE;
                        end else begin
                            wave_byte_count <= wave_byte_count + 1'b1;
                        end
                    end
                end
                ST_SPEC: begin
                    if (!spec_packet_committed && !spec_can_start_new_packet)
                        state <= ST_IDLE;
                    if (source_tcp_accept) begin
                        spec_packet_active <= 1'b1;
                        if (source_buf_spec_last) begin
                            spec_packet_active <= 1'b0;
                            dbg_spec_packet_done_pulse <= 1'b1;
                            if (MIXED_STREAM)begin state<=ST_IDLE;prefer_spec<=0;end
                            else if (!spec_can_start_new_packet)
                                state <= ST_IDLE;
                        end
                    end
                end
                default: begin
                    state <= ST_IDLE;
                    wave_byte_count <= 16'd0;
                    spec_packet_active <= 1'b0;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
