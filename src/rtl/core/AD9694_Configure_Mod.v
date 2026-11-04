`timescale 1ns / 1ps
// AD9694 new-board DC coupling and VCM export; normal JESD acquisition.
// Based on the E-drive demo. SPI engine and top-level ports are unchanged.
// Number_regs is the LAST INDEX: 47 means 48 writes.
// 0x18E3=0x4C assumes the unchanged 0x1A4C/0x1A4D reset value 0x0C.
module AD9694_Configure_Mod
(
    input        clk_50m,  // 五十兆时钟
	 input        rst_n,  // 低有效复位
	              
	 output       spi_rst_p,  // SPI复位
	 output       spi_cs,  // SPI片选
	 output       spi_sclk,  // SPI时钟
	 output       spi_sdo,  // SPI读出数据
	 input        spi_sdi,      // SPI写入数据
     
	 output       SPI_config_OK  // 配置完成
);
//********************************************************
//********************************************************
localparam   IDLE = 16'd0,
             s1   = 16'd1,
             s2   = 16'd2,
             s3   = 16'd3,
             s4   = 16'd4,
             s5   = 16'd5,
             s6   = 16'd6,
             s7   = 16'd7,
             s8   = 16'd8,
             s9   = 16'd9,
             s10  = 16'd10,
             s11  = 16'd11,
             s12  = 16'd12,
             s13  = 16'd13, 
             s14  = 16'd14,
             s15  = 16'd15; 
reg [15:0]   state=IDLE;
//*********************************************************
//*********************************************************
localparam Number_regs=48;

wire [23:0]  write_reg [Number_regs:0];
// Factory demo + new-board DC-coupling/VCM + CMOS SYNC configuration.
// Pair/channel selection is explicitly written before channel/pair-map accesses.
assign write_reg[0 ]  = 24'h000081;  // Soft reset
assign write_reg[1 ]  = 24'h000102;
assign write_reg[2 ]  = 24'h000903;  // Select both ADC pairs AB and CD
assign write_reg[3 ]  = 24'h000803;  // Select both channels in each pair (A/C and B/D)
assign write_reg[4 ]  = 24'h1D0C01;
assign write_reg[5 ]  = 24'h190804;  // 0x1908[2]=1: DC coupling, disconnect internal input common-mode buffer
assign write_reg[6 ]  = 24'h18A600;  // Internal reference mode; release VCM_CD/VREF pin for VCM export
assign write_reg[7 ]  = 24'h18E600;  // Disable temperature-diode export
assign write_reg[8 ]  = 24'h18E004;  // External VCM buffer control 1
assign write_reg[9 ]  = 24'h18E11C;  // External VCM buffer control 2
assign write_reg[10]  = 24'h18E214;  // External VCM buffer control 3
assign write_reg[11]  = 24'h18E34C;  // Enable VCM export; current code 0x0C = 240 uA
assign write_reg[12]  = 24'h1D0D01;
assign write_reg[13]  = 24'h1C2C02;
assign write_reg[14]  = 24'h1D03B0;
assign write_reg[15]  = 24'h1D020B;
assign write_reg[16]  = 24'h1CC017;
assign write_reg[17]  = 24'h1C8008;
assign write_reg[18]  = 24'h1CC601;
assign write_reg[19]  = 24'h000903;
assign write_reg[20]  = 24'h000803;
assign write_reg[21]  = 24'h010800;
assign write_reg[22]  = 24'h1C8B01;
assign write_reg[23]  = 24'h012044;
assign write_reg[24]  = 24'h012004;
assign write_reg[25]  = 24'h012104;
assign write_reg[26]  = 24'h056E00;
assign write_reg[27]  = 24'h057049;  // Factory JESD link config: L=2, M=2, F=2 per ADC pair
assign write_reg[28]  = 24'h057210;  // Normal JESD operation; CMOS single-ended SYNC
assign write_reg[29]  = 24'h057300;
assign write_reg[30]  = 24'h058B81;
assign write_reg[31]  = 24'h058C01;
assign write_reg[32]  = 24'h058E01;
assign write_reg[33]  = 24'h058F0D;
assign write_reg[34]  = 24'h058D1F;
assign write_reg[35]  = 24'h05902F;
assign write_reg[36]  = 24'h05C004;
assign write_reg[37]  = 24'h05C104;
assign write_reg[38]  = 24'h020000; // AD6684：24'h020008 选择VDR模式
assign write_reg[39]  = 24'h020100;
assign write_reg[40]  = 24'h1CF702;
assign write_reg[41]  = 24'h000903;
assign write_reg[42]  = 24'h000803;
assign write_reg[43]  = 24'h1B8510;
assign write_reg[44]  = 24'h1B0138;
assign write_reg[45]  = 24'h000102;
assign write_reg[46]  = 24'h000100;
assign write_reg[47]  = 24'h022946;
assign write_reg[48] = 24'h191000; // 输入满量程2.16 Vpp
wire [23:0]  temp_reg [Number_regs:0];
assign temp_reg[0 ]  = 24'hF00000;
assign temp_reg[1 ]  = 24'hF00000;
assign temp_reg[2 ]  = 24'h000000;
assign temp_reg[3 ]  = 24'h000000;
assign temp_reg[4 ]  = 24'h000000;
assign temp_reg[5 ]  = 24'h000000;
assign temp_reg[6 ]  = 24'h000000;
assign temp_reg[7 ]  = 24'h000000;
assign temp_reg[8 ]  = 24'h000000;
assign temp_reg[9 ]  = 24'h000000;
assign temp_reg[10]  = 24'h000000;
assign temp_reg[11]  = 24'h000000;
assign temp_reg[12]  = 24'h000000;
assign temp_reg[13]  = 24'h000000;
assign temp_reg[14]  = 24'h000000;
assign temp_reg[15]  = 24'h000000;
assign temp_reg[16]  = 24'h000000;
assign temp_reg[17]  = 24'h000000;
assign temp_reg[18]  = 24'h000000;
assign temp_reg[19]  = 24'h000000;
assign temp_reg[20]  = 24'h000000;
assign temp_reg[21]  = 24'h000000;
assign temp_reg[22]  = 24'h000000;
assign temp_reg[23]  = 24'h000000;
assign temp_reg[24]  = 24'h000000;
assign temp_reg[25]  = 24'h000000;
assign temp_reg[26]  = 24'h000000;
assign temp_reg[27]  = 24'h000000;
assign temp_reg[28]  = 24'h000000;
assign temp_reg[29]  = 24'h000000;
assign temp_reg[30]  = 24'h000000;
assign temp_reg[31]  = 24'h000000;
assign temp_reg[32]  = 24'h000000;
assign temp_reg[33]  = 24'h000000;
assign temp_reg[34]  = 24'h000000;
assign temp_reg[35]  = 24'h000000;
assign temp_reg[36]  = 24'h000000;
assign temp_reg[37]  = 24'h000000;
assign temp_reg[38]  = 24'h000000;
assign temp_reg[39]  = 24'h000000;
assign temp_reg[40]  = 24'h000000;
assign temp_reg[41]  = 24'h000000;
assign temp_reg[42]  = 24'h000000;
assign temp_reg[43]  = 24'h000000;
assign temp_reg[44]  = 24'h000000;
assign temp_reg[45]  = 24'hF00000;
assign temp_reg[46]  = 24'hF00000;
assign temp_reg[47]  = 24'hF00000;
assign temp_reg[48] = 24'hF00000; // 沿用末尾条目的处理方式 
reg [7:0]     cnt_reg   = 8'd0;
reg [31:0]    delay_cnt = 0;
reg [31:0]    delay_reg = 16'd0;
reg           wr_en   = 1'b0;
reg           read_en = 1'b0;
reg  [127:0]  data_tr = 128'd0;
wire          spi_locked;
reg [15:0] 	  delay_time  = 16'd0;
//*********************************************************
//*********************************************************
always @ (posedge clk_50m)
begin
  if(!rst_n)
    delay_time<='d0;
  else if(delay_time<1000)
    delay_time<=delay_time+1;
  else
    delay_time<=16'hFFFF;
end
wire    sys_rst_n;
assign  sys_rst_n=(delay_time<200)?1'b0:1'b1;
assign  spi_rst_p=(delay_time<100)?1'b1:1'b0;
//*********************************************************
//*********************************************************
reg spi_config_OK_reg=1'b0;
assign SPI_config_OK=spi_config_OK_reg;
//*********************************************************
//*********************************************************
always @ (posedge clk_50m)
begin
  if(!sys_rst_n)
  begin
    cnt_reg   <= 8'd0;
	 delay_cnt <= 0;
	 state     <= IDLE;
	 wr_en     <= 1'b0;
	 read_en   <= 1'b0;
	 spi_config_OK_reg<=1'b0;
  end
  else
  begin
    case(state)
	 IDLE:begin
			  cnt_reg   <= 8'd0;
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
			  spi_config_OK_reg<=1'b0;
			  if(delay_cnt<100)
			  begin
			     delay_cnt<=delay_cnt+1;
				  state     <= IDLE;
			  end
			  else
			  begin
			     delay_cnt <= 0;
				  state     <= s1;
           end				  
	      end
	 s1  :begin
	       data_tr<={104'd0,write_reg[cnt_reg]};
	       if(delay_cnt<10)
		    begin
			   wr_en     <= 1'b1;
            delay_cnt <= delay_cnt+1;
				state<=state;
          end
          else 
          begin
			   wr_en     <= 1'b0;
            delay_cnt <= 20;
				state<=s2;
          end					               			  
	      end
	  s2 :begin
           if(spi_locked==1'b1)
              state<=s3;
           else
              state<=state;
         end
		s3 :begin
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
	          if(temp_reg[cnt_reg][23]==1'b1)
			  begin
			     
				  state     <= s10;
			  end
			  else
			  begin
				  state     <= s4;
			  end				   
		    end		 
	  s4 :begin
			  delay_cnt <= 0;
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;			  
	        if(cnt_reg<Number_regs)
			  begin
			     cnt_reg   <= cnt_reg + 8'd1;
				  state     <= s5;
			  end
			  else
			  begin
			     cnt_reg   <= 8'd0;
				  state     <= s15;
			  end		  			  
	      end
		  
	  s5:begin
             if(delay_reg<10)
			 begin
			   delay_reg<=delay_reg+1;
			 end
			 else
			 begin
			   delay_reg<=0;
			   state<=s1;
			 end
         end
		s10 :begin
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
	          if(delay_cnt<500000)
		       begin
                delay_cnt <= delay_cnt+1;
				state<=state;
              end
              else 
              begin
                delay_cnt <= 0;
				state<=s4;
              end					
		    end	
		 	     			
	   s15:begin
			  cnt_reg   <= 8'd0;
			  delay_cnt <= 0;

			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
           spi_config_OK_reg<=1'b1;
           state     <= state;	  
		   end	
		   
    endcase
  end
end
//*********************************************************
//*********************************************************
Spi_Control_AD9694_mod #
(
   .ADDR_Width(16'd16),
   .DATA_Width(16'd8)
)
Spi_Control_AD9694_mod_uut
(
    .clk_50m    (clk_50m), 
    .rst_n      (sys_rst_n), 
    .wr_en      (wr_en), 
    .data_tr    (data_tr), 
    .read_en    (1'b0), 
    .data_re    (), 
    .locked     (spi_locked), 
    .cs         (spi_cs), 
    .sclk       (spi_sclk), 
    .sdo        (spi_sdo), 
    .sdi        (spi_sdi), 
    .dbg_wr_en  (1'b0), 
    .dbg_data_in(), 
    .dbg_rd_en  (1'b0), 
    .dbg_data_re(), 
    .dbg_cs     (), 
    .dbg_sclk   (), 
    .dbg_sdo    (), 
    .dbg_sdi    ()
);
//*********************************************************
//*********************************************************


endmodule
