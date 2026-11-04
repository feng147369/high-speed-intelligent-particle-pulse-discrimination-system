`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    22:38:29 04/12/2014 
// Design Name: 
// Module Name:    LMK04828_Configure_ZMM_Mod 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module LMK04828_Configure_ZMM_Mod
(
     input        clk_50m,  // 五十兆时钟
	 input        rst_n,  // 低有效复位
	              
	 output       spi_rst_p,  // SPI复位
	 output       spi_cs,  // SPI片选
	 output       spi_sclk,  // SPI时钟
	 output       spi_sdo,  // SPI读出数据
	 input        spi_sdi,      // SPI写入数据
     
	 output       SPI_config_OK,  // 配置完成
	 input        puls_mode  // 模式选择
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
localparam Number_regs=127;

wire [23:0]  write_reg [Number_regs:0];
assign write_reg[0]   = 24'h000090;
assign write_reg[1]   = 24'h000010;
assign write_reg[2]   = 24'h000200;
assign write_reg[3]   = 24'h000306;
assign write_reg[4]   = 24'h0004D0;
assign write_reg[5]   = 24'h00055B;
assign write_reg[6]   = 24'h000600;
assign write_reg[7]   = 24'h000C51;
assign write_reg[8]   = 24'h000D04;
assign write_reg[9]   = 24'h01000A;
assign write_reg[10]  = 24'h010155;
assign write_reg[11]  = 24'h010255;
assign write_reg[12]  = 24'h010300;
assign write_reg[13]  = 24'h010422;
assign write_reg[14]  = 24'h010500;
assign write_reg[15]  = 24'h0106F0;
assign write_reg[16]  = 24'h010711;
assign write_reg[17]  = 24'h010810;
assign write_reg[18]  = 24'h010955;
assign write_reg[19]  = 24'h010A55;
assign write_reg[20]  = 24'h010B00;
assign write_reg[21]  = 24'h010C22;
assign write_reg[22]  = 24'h010D00;
assign write_reg[23]  = 24'h010EF0;
assign write_reg[24]  = 24'h010F00;
assign write_reg[25]  = 24'h01100A;
assign write_reg[26]  = 24'h011155;
assign write_reg[27]  = 24'h011255;
assign write_reg[28]  = 24'h011300;
assign write_reg[29]  = 24'h011402;
assign write_reg[30]  = 24'h011500;
assign write_reg[31]  = 24'h0116F0;
assign write_reg[32]  = 24'h011701;
assign write_reg[33]  = 24'h01180A;
assign write_reg[34]  = 24'h011955;
assign write_reg[35]  = 24'h011A55;
assign write_reg[36]  = 24'h011B00;
assign write_reg[37]  = 24'h011C02;
assign write_reg[38]  = 24'h011D00;
assign write_reg[39]  = 24'h011EF0;
assign write_reg[40]  = 24'h011F01;
assign write_reg[41]  = 24'h012019;
assign write_reg[42]  = 24'h012155;
assign write_reg[43]  = 24'h012255;
assign write_reg[44]  = 24'h012300;
assign write_reg[45]  = 24'h012422;
assign write_reg[46]  = 24'h012500;
assign write_reg[47]  = 24'h0126F0;
assign write_reg[48]  = 24'h012700;
assign write_reg[49]  = 24'h012805;
assign write_reg[50]  = 24'h012955;
assign write_reg[51]  = 24'h012A55;
assign write_reg[52]  = 24'h012B00;
assign write_reg[53]  = 24'h012C22;
assign write_reg[54]  = 24'h012D00;
assign write_reg[55]  = 24'h012EF0;
assign write_reg[56]  = 24'h012F55;
assign write_reg[57]  = 24'h013019;
assign write_reg[58]  = 24'h013155;
assign write_reg[59]  = 24'h013255;
assign write_reg[60]  = 24'h013300;
assign write_reg[61]  = 24'h013402;
assign write_reg[62]  = 24'h013500;
assign write_reg[63]  = 24'h0136F0;
assign write_reg[64]  = 24'h013700;
assign write_reg[65]  = 24'h013800;
assign write_reg[66]  = 24'h013902;
assign write_reg[67]  = 24'h013A01;
assign write_reg[68]  = 24'h013B40;
assign write_reg[69]  = 24'h013C00;
assign write_reg[70]  = 24'h013D08;
assign write_reg[71]  = 24'h013E03;
assign write_reg[72]  = 24'h013F00;
assign write_reg[73]  = 24'h01400A;
assign write_reg[74]  = 24'h014100;
assign write_reg[75]  = 24'h014200;
assign write_reg[76]  = 24'h014313;
assign write_reg[77]  = 24'h0144FF;
assign write_reg[78]  = 24'h01457F;
assign write_reg[79]  = 24'h014608;
assign write_reg[80]  = 24'h01470A;
assign write_reg[81]  = 24'h014802;
assign write_reg[82]  = 24'h014942;
assign write_reg[83]  = 24'h014A02;
assign write_reg[84]  = 24'h014B32;
assign write_reg[85]  = 24'h014C00;
assign write_reg[86]  = 24'h014D15;     
assign write_reg[87]  = 24'h014ED5;
assign write_reg[88]  = 24'h014F7F;
assign write_reg[89]  = 24'h01501F;
assign write_reg[90]  = 24'h015102;
assign write_reg[91]  = 24'h015200;
assign write_reg[92]  = 24'h015300;
assign write_reg[93]  = 24'h015428;
assign write_reg[94]  = 24'h015500;
assign write_reg[95]  = 24'h015628;
assign write_reg[96]  = 24'h015700;
assign write_reg[97]  = 24'h015828;
assign write_reg[98]  = 24'h015900;
assign write_reg[99]  = 24'h015A64;	
assign write_reg[100] = 24'h015BD4;
assign write_reg[101] = 24'h015C20;
assign write_reg[102] = 24'h015D00;
assign write_reg[103] = 24'h015E00;
assign write_reg[104] = 24'h015F0B;     
assign write_reg[105] = 24'h016000;
assign write_reg[106] = 24'h016101;
assign write_reg[107] = 24'h0162A4;
assign write_reg[108] = 24'h016300;
assign write_reg[109] = 24'h016400;
assign write_reg[110] = 24'h01650C;
assign write_reg[111] = 24'h0171AA;
assign write_reg[112] = 24'h017202;
assign write_reg[113] = 24'h017C15;
assign write_reg[114] = 24'h017D33;
assign write_reg[115] = 24'h016600;
assign write_reg[116] = 24'h016700;
assign write_reg[117] = 24'h016805;
assign write_reg[118] = 24'h016959;
assign write_reg[119] = 24'h016A60;     
assign write_reg[120] = 24'h016B00;
assign write_reg[121] = 24'h016C00;
assign write_reg[122] = 24'h016D00;
assign write_reg[123] = 24'h016E13;
assign write_reg[124] = 24'h017300;
assign write_reg[125] = 24'h018200;
assign write_reg[126] = 24'h018300;
assign write_reg[127] = 24'h018400;

 	

localparam puls_reg=24'h013E03;

	
reg [7:0]     cnt_reg   = 8'd0;
reg [31:0]    delay_cnt = 0;
reg [15:0]    delay_reg = 16'd0;
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
  else if(delay_time<100)
    delay_time<=delay_time+1;
  else
    delay_time<=16'hFFFF;
end
wire    sys_rst_n;
assign  sys_rst_n=(delay_time<20)?1'b0:1'b1;
assign  spi_rst_p=(delay_time<10)?1'b1:1'b0;
//*********************************************************
//*********************************************************
reg spi_config_OK_reg=1'b0;
assign SPI_config_OK=spi_config_OK_reg;
//*********************************************************
//*********************************************************
reg puls_mode_reg;
always @ (posedge clk_50m)
begin
  puls_mode_reg<=puls_mode;
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
			  delay_cnt <= 0;
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;			  
	        if(cnt_reg<Number_regs)
			  begin
			     cnt_reg   <= cnt_reg + 8'd1;
				  state     <= s6;
			  end
			  else
			  begin
			     cnt_reg   <= 8'd0;
				  state     <= s4;
			  end		  			  
	      end
	  s6:begin
             if(delay_reg<100)
			 begin
			   delay_reg<=delay_reg+1;
			 end
			 else
			 begin
			   delay_reg<=0;
			   state<=s1;
			 end
         end	
		s4 :begin
			  cnt_reg   <= 8'd0;
			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
           spi_config_OK_reg<=1'b0;	
	       if(delay_cnt<500000)
		    begin
            delay_cnt <= delay_cnt+1;
				state<=state;
          end
          else 
          begin
            delay_cnt <= 0;
				state<=s5;
          end					
		    end	     			
	   s5:begin
			  cnt_reg   <= 8'd0;
			  delay_cnt <= 0;

			  wr_en     <= 1'b0;
			  read_en   <= 1'b0;	
              spi_config_OK_reg<=1'b1;
			  if(puls_mode_reg==1'b1)
			     state     <= s10;
              else
         		 state     <= state;	  
		   end
	   s10:begin
			   data_tr<={104'd0,puls_reg};
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
					state<=s11;
			  end
           end	
	  s11 :begin
           if(spi_locked==1'b1)
              state<=s5;
           else
              state<=state;
         end		   
    endcase
  end
end
//*********************************************************
//*********************************************************
Spi_Control_LMK04828_mod #
(
   .ADDR_Width(16'd16),
   .DATA_Width(16'd8)
)
Spi_Control_LMK04828_mod_uut
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
