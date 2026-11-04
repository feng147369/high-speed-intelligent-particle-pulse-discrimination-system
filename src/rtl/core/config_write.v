`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2015/02/28 12:03:16
// Design Name: 
// Module Name: config_write
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module config_write(
input           reset,  // 复位信号
input           clk,  // 工作时钟
input           config_start,  // 开始配置
output  [31:0]  config_wr_data,  // 输出数据
output  [11:0]  config_wr_addr,  // 地址信号
output          config_wr_start,  // 启动脉冲
input           config_wr_finish  // 配置写完成
    );
    
    
wire [11:0] addr1 = 12'h008; // 0x008: Support ILA
wire [11:0] addr2 = 12'h00C;  // 0x00C: Scrambling dissabled
wire [11:0] addr3 = 12'h010; // 0x010: Sysref once
wire [11:0] addr4 = 12'h018;  // 0x018: Test mode = Normal operation
wire [11:0] addr5 = 12'h020; // 0x020: Octets per Frame F=2
wire [11:0] addr6 = 12'h024;   // 0x024: Frames per Multiframe K=32
wire [11:0] addr7 = 12'h028;  // 0x028: Lanes in use
wire [11:0] addr8 = 12'h02C;  // 0x02C: Device subclass 1
wire [11:0] addr9 = 12'h030; // 0x030: Rx buffer delay
wire [11:0] addr10 = 12'h034; // 0x034: Error reporting via ~sync    
wire [11:0] addr11 = 12'h004;   // 0x04: Write reset

wire [31:0] data1 = 32'h00000001; // 0x008: Support ILA
wire [31:0] data2 = 32'h00000001;  // 0x00C: Scrambling enabled
wire [31:0] data3 = 32'h00000000; // 0x010: Sysref once
wire [31:0] data4 = 32'h00000000;  // 0x018: Test mode = Normal operation
wire [31:0] data5 = 32'h00000001; // 0x020: Octets per Frame F=2
wire [31:0] data6 = 32'h0000001F; // 0x024: Frames per Multiframe K=32
wire [31:0] data7 = 32'h00000004; // Enable only FPGA Lane 2: board CH1 / ADC D (PCB CD swap)
wire [31:0] data8 = 32'h00000001; // 0x02C: Device subclass 1
wire [31:0] data9 = 32'h00000000; // 0x030: Rx buffer delay
wire [31:0] data10 = 32'h00000000; // 0x034: Error reporting via ~sync   
wire [31:0] data11 = 32'h00000001; // 0x04: Write reset

reg [2:0]       c_state,n_state;   
reg [31:0]      config_wr_data;
reg [11:0]      config_wr_addr;
reg             config_wr_start;  
parameter 	     idle       =0,
                 send       =1,
                 send_over   =2;
reg         first_config;
reg         first_config_flag;    
reg [3:0]   addr_cnt;
                              
                            
always @(posedge clk)                      
if(reset) 
    first_config_flag <= 1'b0;                    
else if(c_state[send])
    first_config_flag <= 1'b1; // if config finished, the flag is 1  
else
    first_config_flag <= first_config_flag;   
       
always @(posedge clk)
    if(reset) 
        first_config <= 1'b0;
    else 
        first_config <= ((config_start)& (~first_config_flag));         
                
always @(posedge clk)
    if(reset) 
        c_state <= 3'h1;
    else 
        c_state <= n_state;                                      

always @(*)
    begin
        n_state <= 3'h0;
        case(1'b1)//synthesis parallel_case
            c_state[idle]:
                if(first_config) 
                    n_state[send] <= 1'b1;
                else
                    n_state[idle] <= 1'b1;
            c_state[send]:
                if(config_wr_finish)
                    n_state[send_over] <= 1'b1;
               else 
                    n_state[send] <= 1'b1;
            c_state[send_over]:
                if(addr_cnt==4'ha)
                    n_state[idle] <= 1'b1;
                else
                    n_state[send] <= 1'b1;
            default: n_state[idle] <= 1'b1;
        endcase
    end
    
always @(posedge clk)                      
    if(reset) 
        addr_cnt <= 4'h0;    
    else if(c_state[idle])
        addr_cnt <= 4'h0;               
    else if(c_state[send_over])
        addr_cnt <= addr_cnt + 1'b1; // if config finished, the flag is 1  
    else
        addr_cnt <= addr_cnt;   

always @(posedge clk)
    if(reset)
        config_wr_data <= 32'h0;
    else
        case({c_state[send], addr_cnt})
            5'b10000:   config_wr_data <= data1;
            5'b10001:   config_wr_data <= data2;
            5'b10010:   config_wr_data <= data3;
            5'b10011:   config_wr_data <= data4;
            5'b10100:   config_wr_data <= data5;
            5'b10101:   config_wr_data <= data6;
            5'b10110:   config_wr_data <= data7;
            5'b10111:   config_wr_data <= data8;
            5'b11000:   config_wr_data <= data9;
            5'b11001:   config_wr_data <= data10;
            5'b11010:   config_wr_data <= data11;
            default:    config_wr_data <= 32'h0;
        endcase
        
always @(posedge clk)
    if(reset)
        config_wr_addr <= 12'h0;
    else
        case({c_state[send], addr_cnt})
            5'b10000:   config_wr_addr <= addr1;
            5'b10001:   config_wr_addr <= addr2;
            5'b10010:   config_wr_addr <= addr3;
            5'b10011:   config_wr_addr <= addr4;
            5'b10100:   config_wr_addr <= addr5;
            5'b10101:   config_wr_addr <= addr6;
            5'b10110:   config_wr_addr <= addr7;
            5'b10111:   config_wr_addr <= addr8;
            5'b11000:   config_wr_addr <= addr9;
            5'b11001:   config_wr_addr <= addr10;
            5'b11010:   config_wr_addr <= addr11;
            default:    config_wr_addr <= 12'h0;
        endcase            
        
always @(posedge clk)                      
    if(reset) 
        config_wr_start <= 1'b0;                    
    else if(c_state[send])
        config_wr_start <= 1'b1; // if config finished, the flag is 1  
    else
        config_wr_start <= 1'b0;           




            
endmodule
