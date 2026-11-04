`timescale 1ns / 1ps


module axi_read_write
(
input           reset,  // 复位信号
input           clk,  // 工作时钟
input   [31:0]  config_wr_data,  // 输入数据
input   [11:0]  config_wr_addr,  // 地址信号
input           config_wr_start,  // 启动脉冲
output          config_wr_finish,  // 配置写完成
output  [31:0]  config_data_out,  // 配置输出数据
input   [11:0]  config_rd_addr,  // 地址信号
input           config_rd_start,  // 启动脉冲
output          config_rd_finish,  // 配置读完成
// axi bus signals   
output          s_axi_aresetn,  // 总线复位
output  [11:0]  s_axi_awaddr,  // 写地址
output          s_axi_awvalid,  // 写地址有效
input           s_axi_awready,  // 写地址就绪
output  [31:0]  s_axi_wdata,  // 写数据
output  [3:0]   s_axi_wstrb,  // 写字节选通
output          s_axi_wvalid,  // 写数据有效
input           s_axi_wready,  // 写数据就绪
input   [1:0]   s_axi_bresp,  // 写响应
input           s_axi_bvalid,  // 写响应有效
output          s_axi_bready,  // 写响应就绪
output  [11:0]  s_axi_araddr,  // 读地址
output          s_axi_arvalid,  // 读地址有效
input           s_axi_arready,  // 读地址就绪
input   [31:0]  s_axi_rdata,  // 读数据
input   [1:0]   s_axi_rresp,  // 读响应
input           s_axi_rvalid,  // 读数据有效
output          s_axi_rready  // 读数据就绪

    );

reg [6:0]       c_wr_state,n_wr_state;   
parameter 	     wr_idle                   =0,
                 wr_write_addr_data        =1,
                 wr_addr_ready         =2,
                 wr_data_ready        =3,
                 wr_bvalid            =4,
                 wr_delay                  =5,
                 wr_delay1                  =6;
reg             config_wr_finish;
//reg [31:0]      config_data_out;
reg             config_rd_finish;
reg [11:0]      s_axi_awaddr;
reg             s_axi_awvalid;
reg [31:0]      s_axi_wdata;
reg [3:0]       s_axi_wstrb;
reg             s_axi_wvalid;
reg [11:0]      s_axi_araddr;
reg             s_axi_arvalid;
                 
assign s_axi_aresetn = ~reset;
                 
always @(posedge clk)
    if(reset) 
        c_wr_state <= 7'h01;
    else 
        c_wr_state <= n_wr_state;
                     
always @(*)
    begin
        n_wr_state <= 7'h00;
        case(1'b1)//synthesis parallel_case
            c_wr_state[wr_idle]:
                if(config_wr_start) 
                    n_wr_state[wr_write_addr_data] <= 1'b1;
                else 
                    n_wr_state[wr_idle] <= 1'b1;  
            c_wr_state[wr_write_addr_data]:
                if(s_axi_awready) 
                    n_wr_state[wr_addr_ready] <= 1'b1;
                else 
                    n_wr_state[wr_write_addr_data] <= 1'b1;  
            c_wr_state[wr_addr_ready]:
                if(s_axi_wready) 
                    n_wr_state[wr_data_ready] <= 1'b1;
                else 
                    n_wr_state[wr_addr_ready] <= 1'b1;  
            c_wr_state[wr_data_ready]:
                if(s_axi_bvalid) 
                    n_wr_state[wr_bvalid] <= 1'b1;
                else 
                    n_wr_state[wr_data_ready] <= 1'b1;  
            c_wr_state[wr_bvalid]:
                    n_wr_state[wr_delay] <= 1'b1;
            c_wr_state[wr_delay]:
                    n_wr_state[wr_delay1] <= 1'b1;
            c_wr_state[wr_delay1]:
                    n_wr_state[wr_idle] <= 1'b1;
            default:n_wr_state[wr_idle] <= 1'b1;
        endcase
    end                 
                 
always @(posedge clk)
    if(reset) begin 
        s_axi_awaddr <= 12'b0;
        s_axi_awvalid <= 1'b0;
        s_axi_wdata <= 32'b0;
        s_axi_wvalid <= 1'b0;
        s_axi_wstrb <= 4'b0;
    end else if(c_wr_state[wr_write_addr_data]) begin
        s_axi_awaddr <= config_wr_addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata <= config_wr_data;
        s_axi_wvalid <= 1'b1;
        s_axi_wstrb <= 4'b1;
    end else if(c_wr_state[wr_addr_ready]) begin
        s_axi_awaddr <= 12'b0;
        s_axi_awvalid <= 1'b0;
        s_axi_wdata <= config_wr_data;
        s_axi_wvalid <= 1'b1;
        s_axi_wstrb <= 4'b1;
    end else begin
        s_axi_awaddr <= 12'b0;
        s_axi_awvalid <= 1'b0;
        s_axi_wdata <= 32'b0;
        s_axi_wvalid <= 1'b0;
        s_axi_wstrb <= 4'b0;
    end
always @(posedge clk)
        if(reset)
            config_wr_finish <= 1'b0;
        else if(c_wr_state[wr_bvalid]) 
            config_wr_finish <= 1'b1;
        else
            config_wr_finish <= 1'b0; 

assign s_axi_bready = 1'b1;    
reg [5:0]       c_rd_state,n_rd_state;   
parameter 	     rd_idle                =0,
                 rd_write_addr          =1,
                 rd_addr_ready          =2,
                 rd_data_ready          =3,
                 rd_delay               =4,
                 rd_delay1               =5;
                 
always @(posedge clk)
    if(reset) 
        c_rd_state <= 6'h01;
    else 
        c_rd_state <= n_rd_state;
                     
always @(*)
    begin
        n_rd_state <= 6'h00;
        case(1'b1)//synthesis parallel_case
            c_rd_state[rd_idle]:
                if(config_rd_start) 
                    n_rd_state[rd_write_addr] <= 1'b1;
                else 
                    n_rd_state[rd_idle] <= 1'b1;  
            c_rd_state[rd_write_addr]:
                if(s_axi_arready) 
                    n_rd_state[rd_addr_ready] <= 1'b1;
                else 
                    n_rd_state[rd_write_addr] <= 1'b1;  
            c_rd_state[rd_addr_ready]:
                if(s_axi_rvalid) 
                    n_rd_state[rd_data_ready] <= 1'b1;
                else 
                    n_rd_state[rd_addr_ready] <= 1'b1; 
            c_rd_state[rd_data_ready]:
                    n_rd_state[rd_delay] <= 1'b1;
            c_rd_state[rd_delay]:
                    n_rd_state[rd_delay1] <= 1'b1;
            c_rd_state[rd_delay1]:
                    n_rd_state[rd_idle] <= 1'b1;
            default:n_rd_state[rd_idle] <= 1'b1;
        endcase
    end                                     
                    
always @(posedge clk)
    if(reset) begin 
        s_axi_araddr <= 12'b0;
        s_axi_arvalid <= 1'b0;
    end else if(c_rd_state[rd_write_addr]) begin
        s_axi_araddr <= config_rd_addr;
        s_axi_arvalid <= 1'b1;
    end else begin
        s_axi_araddr <= 12'b0;
        s_axi_arvalid <= 1'b0;
    end  

assign config_data_out = s_axi_rdata;
assign s_axi_rready = 1'b1;

always @(posedge clk)
    if(reset)
        config_rd_finish <= 1'b0;
    else if(c_rd_state[rd_data_ready]) 
        config_rd_finish <= 1'b1;
    else
        config_rd_finish <= 1'b0;         
   


endmodule
