`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:17:31 01/20/2022 
// Design Name: 
// Module Name:    SpectrumOperate 
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
module SpectrumOperate(
	 input clkin,// 输入时钟
	 input rst_n,  // 低有效复位
	 input [7:0] vary_located ,// 道数档位
	 // data from findpeak module
	 input [15:0] FPDatain,  // 寻峰输入数据
	 input        voltage_range,  // 电压量程
	 input FPEn,  // 寻峰使能
	 input RST,  // 复位信号
	 input [7:0] data_AorB_r,  // 输入数据
	//data exchange with ram_data and ram_out
	 input [31:0] ramDatain,  // 存储数据
	 output ramEn_data,  // 存储数据
	 output ramEn_out,  // 存储使能
	 output [13:0] ramAddr_data,  // 存储地址
	 output [13:0] ramAddr_out,  // 存储地址
	 output [31:0] Data2ram_data,  // 写入RAM数据
	 output [31:0] Data2ram_out,  // 写RAM控制
	 output ramRSTA_data,  // 存储数据
	 output ramRSTA_out,   // 存储复位
	 output ramWea_data,  // 存储数据
	 output ramWea_out,  // 存储写使能
	// cmd 
	input  cmd_control,  // 命令控制
	input  instr_done,// 指令完成
	input [15:0] cmd_spectrumperiod,  // 能谱控制信号
	 // ★★★ 新增调试输出 ★★★
	 output [11:0] dbg_state,      // 调试状态
	 output [13:0] dbg_addr,       // 调试地址
	 output [13:0] dbg_tmp_addr,   // 调试暂存地址
	 output [31:0] dbg_tmp_dataout,// 调试累计值
	 output [3:0]  dbg_count,      // 调试计数
	 output        dbg_flag_instr  // 调试信号
	 );
	 
	 //配置总道址  最终道址为8192道
	 wire [13:0] AddrMax;
	 assign AddrMax = ((16384>>vary_located)-1);//0-8191
	 wire [13:0] addr;
	 assign addr =({FPDatain[15:1]}>>voltage_range); //2^13=8192道
	 
	 //assign addr =256<<X;X表示道址//输入一个8位的数据控制地址的转换

	//能谱测量时间
	reg ms_en;
	reg [23:0] time_count;
	reg [31:0] tmp_timecount=32'b0;
	parameter mscount = 24'd49999;
	//1ms gengerate
	always @(posedge clkin )
		begin 
			time_count <= time_count+24'h1;
			if(time_count > mscount ) begin
				ms_en <= 1'b1;
				time_count <= 24'b0;
				end
			else 
				ms_en <= 1'b0;
		end
		
		reg Spectrum_en;	
		reg cmd_control_r;
    always@(posedge clkin)begin
      cmd_control_r<=cmd_control;
      end
	always @(posedge clkin )
		begin	
			if(~rst_n||RST) begin
			    tmp_timecount <= 32'b0;
				Spectrum_en <= 1'b0;
				end
			else begin 
				if((tmp_timecount <=499999999)&&cmd_control) begin
					Spectrum_en <= 1'b1;
					tmp_timecount <= tmp_timecount+1'b1;
					end
				else begin 
//				    tmp_timecount <= 32'b0;
					Spectrum_en <= 1'b0;
			end
				end
		end
	//instr_done 的指令信号
// 用你的复位脉冲做谱清零触发(替代师兄的 instr_done)
reg flag_instr;
reg reset_done;
always@(posedge clkin) begin 
    if(~rst_n||RST) flag_instr <= 1'b1;     // 上电先清一次谱
    else begin
        if(instr_done) flag_instr <= 1'b1;   // instr_done 这里接你的 o_reset_pulse
        else if(reset_done) flag_instr <= 1'b0;
    end
end
	
	parameter RESET     	= 12'h001;
	parameter RESET_ADDR	= 12'h002;
	parameter JUDGE     	= 12'h004;
	parameter IDLE      	= 12'h008;
	parameter ADDR_RAM  	= 12'h010;

	reg [11:0] state;
	reg tmp_wea_data,tmp_wea_out,tmp_rst_data, tmp_rst_out,tmp_en_data, tmp_en_out;
	reg [14:0] addrloop;
	reg [13:0] tmp_addr;
	reg [31:0] tmp_data, tmp_dataout;
    reg [3:0] count;
	
	
	assign 	 ramEn_data  = tmp_en_data; //ram1的读使能
	assign 	 ramEn_out   = tmp_en_out;//ram2的读使能
	
	assign   ramRSTA_data = tmp_rst_data;//ram1的复位信号
	assign   ramRSTA_out = tmp_rst_out;//ram2的复位信号
	
	assign   ramWea_data  = tmp_wea_data;//ram1的写请求
	assign   ramWea_out  = tmp_wea_out;//ram2的写请求
	
	assign   Data2ram_data = (tmp_wea_data==1'b1)?tmp_dataout:32'b0;//ram1的数据写入
	assign   Data2ram_out = (tmp_wea_out==1'b1)?tmp_dataout:32'b0;//ram2的数据写入
	
	assign   ramAddr_data  = (tmp_en_data ==1'b1)?tmp_addr:14'b0;//ram1的地址
	assign   ramAddr_out  = (tmp_en_out ==1'b1)?tmp_addr:14'b0;//ram2的写入地址
	
//	always@(posedge clkin )
//		begin
//		if(~rst_n)
//			count <= 4'd0;
//		else begin 
//			if(state >= ADDR_RAM)
//				count <= count + 1'b1;
//			else
//				count <= 4'd0;
//			end
//		end
		
	always@(posedge clkin )
		begin
		if(~rst_n||RST)
//		if(~rst_n)
			state <= RESET;
		else begin
			case(state)
				RESET: begin 
					tmp_en_data  <= 1'b1;
					tmp_en_out   <= 1'b1;
					tmp_wea_data <= 1'b1;
					tmp_wea_out  <= 1'b1;
					tmp_rst_data <= 1'b1;
					tmp_rst_out  <= 1'b1;
					tmp_dataout <= 32'b0;
					tmp_addr <= addrloop;
					state <= RESET_ADDR;
					end
				RESET_ADDR: begin
					addrloop <= addrloop +1'b1;
					tmp_en_data <= 1'b0;
					tmp_en_out  <= 1'b0;
					if(addrloop < 'd16384)
						state <= RESET;
					else begin
						reset_done <= 1'b1;
						addrloop <= 14'b0;
						state <= JUDGE;
						end
					end
				JUDGE: begin
					tmp_en_data  <= 1'b0;
					tmp_en_out   <= 1'b0;
					tmp_wea_data <= 1'b0;
					tmp_wea_out  <= 1'b0;
					tmp_rst_data <= 1'b0;
					tmp_rst_out  <= 1'b0;
					reset_done <= 1'b0;
						if(data_AorB_r[0]==1'b1)begin
						if(cmd_control)
							begin	
								if(flag_instr)//
									state <= RESET;//
								else begin//
								
								
//									if(Spectrum_en) begin
										state <= IDLE;//
//										end
//									else begin
//										state <= JUDGE;
										end//
//									end
							end
						else begin
							state <= JUDGE;
							end
					end
					else begin 
					   state <= JUDGE;
					  end
					end
				IDLE: begin
						if(FPEn) begin
							state <= ADDR_RAM;
							count<=4'd0;
							end
						else
							state <= IDLE;
						end
				ADDR_RAM: begin
				                count <= count + 1'b1;
								case(count)
								4'd0: begin tmp_addr <= (addr>>vary_located); end//tmp_wea_data控制ram1的写请求和写数据
								4'd1: begin tmp_en_data <= 1'b1;  tmp_wea_data  <= 1'b0; tmp_dataout <= 32'h0; tmp_data <= 32'h0; end//tmp_en_data控制ram1的地址和读使能
								4'd2: begin tmp_en_data <= 1'b1;  tmp_data <= ramDatain; end//ramDatain ram1的数据
								4'd3: begin tmp_en_data <= 1'b1;  tmp_data <= ramDatain; end
								4'd4: begin tmp_en_data <= 1'b1;  tmp_data <= ramDatain; end
								4'd5: begin tmp_en_data   <= 1'b1;  tmp_en_out   <= 1'b0; tmp_dataout <= tmp_data + 1'b1; end
								4'd6: begin tmp_en_data   <= 1'b1;  tmp_en_out   <= 1'b1; end
								4'd7: begin tmp_wea_data  <= 1'b1;  tmp_wea_out  <= 1'b1; end
								4'd8: begin tmp_wea_data  <= 1'b1;  tmp_wea_out  <= 1'b1; end
								4'd9: begin tmp_wea_data  <= 1'b0;  tmp_wea_out  <= 1'b0; end
								4'd10: begin tmp_en_data   <= 1'b0;  tmp_en_out   <= 1'b0; end
								4'd11: begin tmp_addr <= 14'b0;  tmp_dataout <= 32'b0; count<=4'd0; state <= JUDGE; end
								default: begin state <= JUDGE; end
								endcase
							end
				default: begin state <=JUDGE; end
				endcase
			end
		end
//		ila_4 ila_4 (
//	.clk(clkin), // input wire clk


//	.probe0({tmp_addr,AddrMax,count,vary_located})

//);
//ila_1 ila_1 (
//	.clk(clkin), // input wire clk


//	.probe0({tmp_wea_data,tmp_dataout}) // input wire [32:0] probe0
//);

// ★★★ 调试输出连接 ★★★
assign dbg_state       = state;
assign dbg_addr        = addr;
assign dbg_tmp_addr    = tmp_addr;
assign dbg_tmp_dataout = tmp_dataout;
assign dbg_count       = count;
assign dbg_flag_instr  = flag_instr;

endmodule