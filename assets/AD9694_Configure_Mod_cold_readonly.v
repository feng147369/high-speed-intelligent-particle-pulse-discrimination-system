`timescale 1ns / 1ps
// IDENTITY-ONLY BITSTREAM. Four READ frames; no ADC writes or soft reset.
// Replaces Configure only; compatible with the current demo top and ILA IP.
// clk_50m is connected to clk_100m in this demo.
module AD9694_Configure_Mod #(
    parameter integer HALF_CYCLES=500,
    parameter integer STARTUP_WAIT_CYCLES=2000000,
    parameter integer TIMEOUT_CYCLES=1000000
)(
    input wire clk_50m, input wire rst_n,
    output wire spi_rst_p, output wire spi_cs, output wire spi_sclk,
    output wire spi_sdo, output wire spi_oe, input wire spi_sdi,
    output wire SPI_config_OK
);
    wire clk=clk_50m;
    // Normal acquisition deliberately remains disabled in this image.
    assign SPI_config_OK=1'b0;
    assign spi_rst_p=1'b0;
    localparam WAIT_POWER=0,LOAD=1,LAUNCH=2,WAIT_DONE=3,SAVE=4,FINISH=5;
    reg [2:0] state=WAIT_POWER;
    reg [5:0] por_step=0;
    reg [31:0] wait_count=0, timeout_count=0;
    reg start=0, por_done=0, por_fault=0;
    reg [23:0] command=24'h800400;
    wire engine_done, engine_busy;
    wire [7:0] rx;
    reg [7:0] por_chip_id=0, por_mode=0;
    reg [7:0] por_chip_id_repeat=0, por_mode_repeat=0;
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=WAIT_POWER; por_step<=0; wait_count<=0;
            timeout_count<=0; start<=0; por_done<=0; por_fault<=0;
            command<=24'h800400;
            por_chip_id<=0; por_mode<=0;
            por_chip_id_repeat<=0; por_mode_repeat<=0;
        end else begin
            start<=0;
            case(state)
                WAIT_POWER: begin
                    if (wait_count==STARTUP_WAIT_CYCLES-1) state<=LOAD;
                    else wait_count<=wait_count+1;
                end
                LOAD: begin
                    // 8004=read 0004; 8200=read 0200. Never writes 0009.
                    command<=por_step[0] ? 24'h820000 : 24'h800400;
                    timeout_count<=0; state<=LAUNCH;
                end
                LAUNCH: begin start<=1; state<=WAIT_DONE; end
                WAIT_DONE: begin
                    if (engine_done) state<=SAVE;
                    else if (timeout_count==TIMEOUT_CYCLES-1) begin
                        por_fault<=1; por_done<=1; state<=FINISH;
                    end else timeout_count<=timeout_count+1;
                end
                SAVE: begin
                    case(por_step)
                        0: por_chip_id<=rx;
                        1: por_mode<=rx;
                        2: por_chip_id_repeat<=rx;
                        3: por_mode_repeat<=rx;
                    endcase
                    if (por_step==3) begin por_done<=1; state<=FINISH; end
                    else begin por_step<=por_step+1; state<=LOAD; end
                end
                FINISH: begin start<=0; end
                default: begin por_fault<=1; por_done<=1; state<=FINISH; end
            endcase
        end
    end
    ADC_POR_Byte_Master #(.HALF_CYCLES(HALF_CYCLES)) master (
        .clk(clk),.rst_n(rst_n && !por_fault),.start(start),.command(command),
        .sdio_i(spi_sdi),.cs(spi_cs),.sclk(spi_sclk),
        .sdio_o(spi_sdo),.sdio_oe(spi_oe),.rx(rx),
        .done(engine_done),.busy(engine_busy)
    );
    // Passive CS/SCLK/SDIO observer. No use of command or master.rx.
    reg cs_d=1,sclk_d=0;
    reg [5:0] frame_step=0, edge_count=0;
    reg [23:0] frame_shift=0, por_id_frame=0, por_mode_frame=0;
    reg [7:0] mid_shift=0, por_id_mid=0, por_mode_mid=0;
    reg [31:0] mid_count=0;
    reg mid_pending=0, all_frames_24=1, all_frames_readonly=1;
    reg [2:0] frames_seen=0;
    always @(posedge clk) begin
        if (!rst_n) begin
            cs_d<=1;sclk_d<=0;frame_step<=0;edge_count<=0;
            frame_shift<=0;por_id_frame<=0;por_mode_frame<=0;
            mid_shift<=0;por_id_mid<=0;por_mode_mid<=0;
            mid_count<=0;mid_pending<=0;
            all_frames_24<=1;all_frames_readonly<=1;frames_seen<=0;
        end else begin
            cs_d<=spi_cs;sclk_d<=spi_sclk;
            if (cs_d && !spi_cs) begin
                frame_step<=por_step;edge_count<=0;frame_shift<=0;
                mid_shift<=0;mid_count<=0;mid_pending<=0;
            end else if (!spi_cs) begin
                if (!sclk_d && spi_sclk) begin
                    frame_shift<={frame_shift[22:0],spi_sdi};
                    edge_count<=edge_count+1;
                    if (edge_count>=16 && edge_count<24) begin
                        mid_pending<=1;mid_count<=0;
                    end
                end
                if (mid_pending) begin
                    if (mid_count==(HALF_CYCLES/2)-1) begin
                        mid_shift<={mid_shift[6:0],spi_sdi};mid_pending<=0;
                    end else mid_count<=mid_count+1;
                end
            end
            if (!cs_d && spi_cs) begin
                frames_seen<=frames_seen+1;mid_pending<=0;
                all_frames_24<=all_frames_24 && (edge_count==24);
                all_frames_readonly<=all_frames_readonly &&
                    (frame_shift[23:8]==(frame_step[0]?16'h8200:16'h8004));
                if (frame_step==0) begin
                    por_id_frame<=frame_shift;por_id_mid<=mid_shift;
                end
                if (frame_step==1) begin
                    por_mode_frame<=frame_shift;por_mode_mid<=mid_shift;
                end
            end
        end
    end
    wire [7:0] por_id_instruction_hi=por_id_frame[23:16];
    wire [7:0] por_id_instruction_lo=por_id_frame[15:8];
    wire [7:0] por_mode_instruction_hi=por_mode_frame[23:16];
    wire [7:0] por_mode_instruction_lo=por_mode_frame[15:8];
    wire [7:0] por_id_raw=por_id_frame[7:0];
    wire [7:0] por_mode_raw=por_mode_frame[7:0];
    wire [1:0] por_repeat_ok={
        (por_mode==por_mode_repeat),(por_chip_id==por_chip_id_repeat)};
    wire [7:0] por_flags={2'b00,
        (all_frames_readonly && frames_seen==4),
        (por_id_frame[23:8]==16'h8004),
        (por_mode_frame[23:8]==16'h8200),
        (all_frames_24 && frames_seen==4),por_fault,por_done};
    wire [7:0] por_spi_monitor={3'b000,engine_busy,spi_cs,spi_sclk,spi_oe,spi_sdi};
    ila_adc_spi ila_adc_spi_inst (
        .clk(clk),
        .probe0(por_chip_id),.probe1(por_mode),
        .probe2(por_chip_id_repeat),.probe3(por_mode_repeat),
        .probe4(por_id_instruction_hi),.probe5(por_id_instruction_lo),
        .probe6(por_mode_instruction_hi),.probe7(por_mode_instruction_lo),
        .probe8(por_id_raw),.probe9(por_mode_raw),
        .probe10(por_id_mid),.probe11(por_mode_mid),
        .probe12(por_repeat_ok),.probe13(por_flags),
        .probe14(por_spi_monitor),.probe15(por_step)
    );
endmodule

// SPI mode 0, one-byte register access, exactly 24 SCLK rising edges.
// FPGA releases SDIO during the high period after instruction bit A0.
// ADC changes read data on falling edges; FPGA samples on rising edges.
module ADC_POR_Byte_Master #(
    parameter integer HALF_CYCLES=50
)(
    input wire clk, input wire rst_n, input wire start,
    input wire [23:0] command, input wire sdio_i,
    output reg cs, output reg sclk,
    output reg sdio_o, output reg sdio_oe,
    output reg [7:0] rx, output reg done, output reg busy
);
    localparam IDLE=0, LOW_PHASE=1, HIGH_PHASE=2, HOLD_CS=3, GAP=4;
    reg [2:0] state=IDLE;
    reg [31:0] count=0;
    reg [4:0] bit_index=23;
    reg [23:0] tx=0;
    reg is_read=0;
    // HALF_CYCLES must be >=6: provides a hold interval before SDIO release.
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; count<=0; bit_index<=23; tx<=0; is_read<=0;
            cs<=1; sclk<=0; sdio_o<=0; sdio_oe<=0;
            rx<=0; done<=0; busy<=0;
        end else begin
            done<=0;
            case (state)
                IDLE: begin
                    cs<=1; sclk<=0; sdio_oe<=0; busy<=0; count<=0;
                    if (start) begin
                        tx<=command; is_read<=command[23]; bit_index<=23;
                        rx<=0; busy<=1; cs<=0; sdio_oe<=1;
                        sdio_o<=command[23]; state<=LOW_PHASE;
                    end
                end
                LOW_PHASE: begin
                    if (count==HALF_CYCLES-1) begin
                        count<=0; sclk<=1; state<=HIGH_PHASE;
                        if (is_read && bit_index<8) rx<={rx[6:0],sdio_i};
                    end else count<=count+1;
                end
                HIGH_PHASE: begin
                    // A0 was latched on the previous rising edge. Allow
                    // three fabric cycles of hold before releasing SDIO.
                    if (is_read && bit_index==8 && count==2) sdio_oe<=0;
                    if (count==HALF_CYCLES-1) begin
                        count<=0; sclk<=0;
                        if (bit_index==0) state<=HOLD_CS;
                        else begin
                            bit_index<=bit_index-1;
                            if (!is_read || bit_index>8)
                                sdio_o<=tx[bit_index-1];
                            state<=LOW_PHASE;
                        end
                    end else count<=count+1;
                end
                HOLD_CS: begin
                    if (count==HALF_CYCLES-1) begin
                        cs<=1; sdio_oe<=0; count<=0; state<=GAP;
                    end else count<=count+1;
                end
                GAP: begin
                    if (count==HALF_CYCLES-1) begin
                        count<=0; done<=1; busy<=0; state<=IDLE;
                    end else count<=count+1;
                end
                default: begin state<=IDLE; cs<=1; sclk<=0; sdio_oe<=0; busy<=0; end
            endcase
        end
    end
endmodule
