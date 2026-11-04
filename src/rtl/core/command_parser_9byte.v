
`timescale 1ns / 1ps

module command_parser_9byte #(
    parameter MODE_INTERLOCK = 0,
    parameter signed [31:0] DEFAULT_AI_THRESHOLD = 32'sd0,
    parameter [15:0] DEFAULT_WAVE_THRESHOLD = 16'd500,
    parameter [15:0] DEFAULT_WAVE_SAMPLES   = 16'd256,

    parameter [15:0] DEFAULT_SPEC_ADDR_CODE = 16'h0003,
    
    parameter [15:0] DEFAULT_TOTAL_GATE_CYC  = 16'd256,
    
    parameter [15:0] DEFAULT_PSD_THRESHOLD_X100 = 16'd70,

    parameter        DEFAULT_WORK_MODE      = 1'b0,

    parameter [7:0]  DEFAULT_WAVE_SUBMODE   = 8'hA0
)(
    input wire i_switch_safe,
    output reg o_ai_mode, o_ai_mode_valid,
    output reg signed [31:0] o_ai_threshold,
    input  wire        i_clk,  
    input  wire        i_rst_n,  
    
    input  wire        i_rx_wr,  
    input  wire [7:0]  i_rx_data,  

    output reg         o_run_enable,  
    output reg         o_start_pulse,  
    output reg         o_pause_pulse,  
    output reg         o_clear_pulse,  
    output reg         o_system_reset_pulse,  

    output reg         o_work_mode,  

    output reg  [7:0]  o_wave_submode,  
    output reg         o_mode_set_pulse,  

    output reg  [15:0] o_wave_threshold,  
    output reg         o_wave_threshold_valid,  
    output reg  [15:0] o_wave_sample_points,  
    output reg         o_wave_sample_points_valid,  

    output reg  [15:0] o_spectrum_addr_code,  

    output reg  [13:0] o_spectrum_bins,  
    output reg         o_spectrum_bins_valid,  

    output reg  [15:0] o_total_gate_cycles,  
    output reg         o_total_gate_cycles_valid,  

    output reg  [15:0] o_psd_threshold_x100,  
    output reg         o_psd_threshold_valid,  

    output reg         o_frame_valid,  
    
    output reg         o_frame_error,  
    
    output reg         o_cmd_error,  
    
    output reg  [7:0]  o_last_cmd  
);

    localparam [7:0] CMD_START          = 8'h11;
    localparam [7:0] CMD_PAUSE          = 8'h12;
    localparam [7:0] CMD_CLEAR          = 8'h13;
    localparam [7:0] CMD_WAVE_THRESHOLD = 8'h22;
    localparam [7:0] CMD_WAVE_SAMPLES   = 8'h23;
    localparam [7:0] CMD_SPEC_BINS      = 8'h24;
    localparam [7:0] CMD_TOTAL_GATE      = 8'h27;
    localparam [7:0] CMD_PSD_THRESHOLD   = 8'h28;
    localparam [7:0] CMD_MODE           = 8'h33;
    localparam [7:0] CMD_RESET          = 8'hFA;

    localparam [7:0] WAVE_SINGLE = 8'hA0;
    localparam [7:0] WAVE_NORMAL = 8'hA1;

    localparam [3:0]
        ST_HEAD_A5 = 4'd0,
        ST_HEAD_5A = 4'd1,
        ST_CMD     = 4'd2,
        ST_P1      = 4'd3,
        ST_P2      = 4'd4,
        ST_P3      = 4'd5,
        ST_P4      = 4'd6,
        ST_TAIL_C3 = 4'd7,
        ST_TAIL_3C = 4'd8;

    reg [3:0] state;
    reg [7:0] cmd_reg;
    reg [7:0] p1_reg;
    reg [7:0] p2_reg;
    reg [7:0] p3_reg;
    reg [7:0] p4_reg;

    function [13:0] decode_spectrum_bins;
        input [15:0] code;  
        begin
            case (code)
                16'h0001: decode_spectrum_bins = 14'd1024;
                16'h0002: decode_spectrum_bins = 14'd2048;
                16'h0003: decode_spectrum_bins = 14'd4096;
                16'h0004: decode_spectrum_bins = 14'd8192;
                default:  decode_spectrum_bins = 14'd4096;
            endcase
        end
    endfunction

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_ai_mode<=0; o_ai_mode_valid<=0; o_ai_threshold<=DEFAULT_AI_THRESHOLD;
            state                       <= ST_HEAD_A5;

            cmd_reg                     <= 8'd0;
            p1_reg                      <= 8'd0;
            p2_reg                      <= 8'd0;
            p3_reg                      <= 8'd0;
            p4_reg                      <= 8'd0;

            o_run_enable                <= 1'b0;
            o_start_pulse               <= 1'b0;
            o_pause_pulse               <= 1'b0;
            o_clear_pulse               <= 1'b0;
            o_system_reset_pulse        <= 1'b0;

            o_work_mode                 <= DEFAULT_WORK_MODE;
            o_wave_submode              <= DEFAULT_WAVE_SUBMODE;
            o_mode_set_pulse            <= 1'b0;

            o_wave_threshold            <= DEFAULT_WAVE_THRESHOLD;
            o_wave_threshold_valid      <= 1'b0;

            o_wave_sample_points        <= DEFAULT_WAVE_SAMPLES;
            o_wave_sample_points_valid  <= 1'b0;

            o_spectrum_addr_code        <= DEFAULT_SPEC_ADDR_CODE;
            o_spectrum_bins             <= decode_spectrum_bins(DEFAULT_SPEC_ADDR_CODE);
            o_spectrum_bins_valid       <= 1'b0;

            o_total_gate_cycles         <= DEFAULT_TOTAL_GATE_CYC;
            o_total_gate_cycles_valid   <= 1'b0;
            o_psd_threshold_x100        <= DEFAULT_PSD_THRESHOLD_X100;
            o_psd_threshold_valid       <= 1'b0;

            o_frame_valid               <= 1'b0;
            o_frame_error               <= 1'b0;
            o_cmd_error                 <= 1'b0;
            o_last_cmd                  <= 8'd0;
        end
        else begin

            o_ai_mode_valid<=0;
            o_start_pulse              <= 1'b0;
            o_pause_pulse              <= 1'b0;
            o_clear_pulse              <= 1'b0;
            o_system_reset_pulse       <= 1'b0;

            o_mode_set_pulse           <= 1'b0;
            o_wave_threshold_valid     <= 1'b0;
            o_wave_sample_points_valid <= 1'b0;
            o_spectrum_bins_valid      <= 1'b0;
            o_total_gate_cycles_valid  <= 1'b0;
            o_psd_threshold_valid      <= 1'b0;

            o_frame_valid              <= 1'b0;
            o_frame_error              <= 1'b0;
            o_cmd_error                <= 1'b0;

            if (i_rx_wr) begin
                case (state)

                    ST_HEAD_A5: begin
                        if (i_rx_data == 8'hA5) begin
                            state <= ST_HEAD_5A;
                        end
                    end

                    ST_HEAD_5A: begin
                        if (i_rx_data == 8'h5A) begin
                            state <= ST_CMD;
                        end
                        else if (i_rx_data == 8'hA5) begin
                            
                            state <= ST_HEAD_5A;
                        end
                        else begin
                            o_frame_error <= 1'b1;
                            state         <= ST_HEAD_A5;
                        end
                    end

                    ST_CMD: begin
                        cmd_reg <= i_rx_data;
                        state   <= ST_P1;
                    end

                    ST_P1: begin
                        p1_reg <= i_rx_data;
                        state  <= ST_P2;
                    end

                    ST_P2: begin
                        p2_reg <= i_rx_data;
                        state  <= ST_P3;
                    end

                    ST_P3: begin
                        p3_reg <= i_rx_data;
                        state  <= ST_P4;
                    end

                    ST_P4: begin
                        p4_reg <= i_rx_data;
                        state  <= ST_TAIL_C3;
                    end

                    ST_TAIL_C3: begin
                        if (i_rx_data == 8'hC3) begin
                            state <= ST_TAIL_3C;
                        end
                        else begin
                            o_frame_error <= 1'b1;

                            if (i_rx_data == 8'hA5)
                                state <= ST_HEAD_5A;
                            else
                                state <= ST_HEAD_A5;
                        end
                    end

                    ST_TAIL_3C: begin
                        if (i_rx_data == 8'h3C) begin
                            o_frame_valid <= 1'b1;
                            o_last_cmd    <= cmd_reg;

                            case (cmd_reg)

                                CMD_START: begin
                                    if ((p1_reg == 8'h00) &&
                                        (p2_reg == 8'h00) &&
                                        (p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin

                                        o_run_enable  <= 1'b1;
                                        o_start_pulse <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_PAUSE: begin
                                    if ((p1_reg == 8'h00) &&
                                        (p2_reg == 8'h00) &&
                                        (p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin

                                        o_run_enable  <= 1'b0;
                                        o_pause_pulse <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_CLEAR: begin
                                    if ((p1_reg == 8'h00) &&
                                        (p2_reg == 8'h00) &&
                                        (p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin
                                        o_clear_pulse <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                8'h34: begin
                                    if (!o_run_enable && (!MODE_INTERLOCK || i_switch_safe) &&
                                        p1_reg<=1 && {p2_reg,p3_reg,p4_reg}==0) begin
                                        o_ai_mode<=p1_reg[0];o_ai_mode_valid<=1;
                                    end else o_cmd_error<=1;
                                end
                                8'h35: begin
                                    if(!o_run_enable && (!MODE_INTERLOCK || i_switch_safe)) o_ai_threshold<={p1_reg,p2_reg,p3_reg,p4_reg};
                                    else o_cmd_error<=1;
                                end
                                CMD_RESET: begin
                                    if ((p1_reg == 8'h00) &&
                                        (p2_reg == 8'h00) &&
                                        (p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin
                                        o_ai_mode<=0;o_ai_mode_valid<=1;o_ai_threshold<=DEFAULT_AI_THRESHOLD;
                                        o_run_enable         <= 1'b0;
                                        o_system_reset_pulse <= 1'b1;

                                        o_work_mode          <= DEFAULT_WORK_MODE;
                                        o_wave_submode       <= DEFAULT_WAVE_SUBMODE;

                                        o_wave_threshold     <= DEFAULT_WAVE_THRESHOLD;
                                        o_wave_sample_points <= DEFAULT_WAVE_SAMPLES;

                                        o_spectrum_addr_code <= DEFAULT_SPEC_ADDR_CODE;
                                        o_spectrum_bins      <=
                                            decode_spectrum_bins(
                                                DEFAULT_SPEC_ADDR_CODE
                                            );

                                        o_total_gate_cycles       <= DEFAULT_TOTAL_GATE_CYC;
                                        o_total_gate_cycles_valid <= 1'b1;
                                        o_psd_threshold_x100      <= DEFAULT_PSD_THRESHOLD_X100;
                                        o_psd_threshold_valid     <= 1'b1;

                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_MODE: begin
                                    if(MODE_INTERLOCK && (o_run_enable || !i_switch_safe)) o_cmd_error<=1;
                                    else begin
                                    
                                    if ((p1_reg == 8'h00) &&
                                        ((p2_reg == WAVE_SINGLE) ||
                                         (p2_reg == WAVE_NORMAL)) &&
                                        (p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin

                                        o_work_mode      <= 1'b0;
                                        o_wave_submode   <= p2_reg;
                                        o_mode_set_pulse <= 1'b1;
                                    end
                                    
                                    else if ((p1_reg == 8'h01) &&
                                             (p2_reg == 8'h00) &&
                                             (p3_reg == 8'h00) &&
                                             (p4_reg == 8'h00)) begin
                                        o_work_mode      <= 1'b1;

                                        o_mode_set_pulse <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                    end
                                end

                                CMD_WAVE_THRESHOLD: begin
                                    if ((p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin
                                        o_wave_threshold       <= {p1_reg, p2_reg};
                                        o_wave_threshold_valid <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_WAVE_SAMPLES: begin
                                    if ((p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00) &&
                                        ({p1_reg, p2_reg} <= 16'd2047)) begin

                                        o_wave_sample_points       <= {p1_reg, p2_reg};
                                        o_wave_sample_points_valid <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_SPEC_BINS: begin
                                    if ((p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00)) begin
                                        case ({p1_reg, p2_reg})
                                            16'h0001,
                                            16'h0002,
                                            16'h0003,
                                            16'h0004: begin
                                                o_spectrum_addr_code <=
                                                    {p1_reg, p2_reg};
                                                o_spectrum_bins <=
                                                    decode_spectrum_bins(
                                                        {p1_reg, p2_reg}
                                                    );
                                                o_spectrum_bins_valid <= 1'b1;
                                            end
                                            default: begin
                                                o_cmd_error <= 1'b1;
                                            end
                                        endcase
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_TOTAL_GATE: begin
                                    if ((p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00) &&
                                        ({p1_reg, p2_reg} >= 16'h0001) &&
                                        ({p1_reg, p2_reg} <= 16'h7FFF)) begin
                                        o_total_gate_cycles       <= {p1_reg, p2_reg};
                                        o_total_gate_cycles_valid <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                CMD_PSD_THRESHOLD: begin
                                    if ((p3_reg == 8'h00) &&
                                        (p4_reg == 8'h00) &&
                                        ({p1_reg, p2_reg} >= 16'd1) &&
                                        ({p1_reg, p2_reg} <= 16'd99)) begin
                                        o_psd_threshold_x100  <= {p1_reg, p2_reg};
                                        o_psd_threshold_valid <= 1'b1;
                                    end
                                    else begin
                                        o_cmd_error <= 1'b1;
                                    end
                                end

                                default: begin
                                    o_cmd_error <= 1'b1;
                                end
                            endcase
                            
                            state <= ST_HEAD_A5;
                        end
                        else begin
                            o_frame_error <= 1'b1;
                            
                            if (i_rx_data == 8'hA5)
                                state <= ST_HEAD_5A;
                            else
                                state <= ST_HEAD_A5;
                        end
                    end
                    default: begin
                        state <= ST_HEAD_A5;
                    end
                endcase
            end
        end
    end

endmodule
