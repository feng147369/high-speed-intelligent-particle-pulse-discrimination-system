`timescale 1ns / 1ps

module Spi_Control_LMK04828_mod #
(
   parameter  ADDR_Width=16'd8,
   parameter  DATA_Width=16'd16
)
(
   input          clk_50m,  // 五十兆时钟
	input          rst_n,  // 低有效复位
	input          wr_en,  // 写使能
	input  [127:0] data_tr,  // 输入数据
	
	input          read_en,  // 读使能
   output [127:0] data_re,  // 输出数据
	
   output         locked,	  // 时钟锁定
	
	output         cs,  // 片选信号
	output         sclk,  // SPI时钟
	output         sdo,  // SPI读出数据
	input          sdi,  // SPI写入数据
	
	input          dbg_wr_en,  // 调试信号
	input  [127:0] dbg_data_in,  // 调试信号
	input          dbg_rd_en,  // 调试信号
	output [127:0] dbg_data_re,  // 调试信号
	
	output         dbg_cs,  // 调试信号
	output         dbg_sclk,  // 调试信号
	output         dbg_sdo,  // 调试信号
	output         dbg_sdi  // 调试信号
);
//********************************************************
//********************************************************
localparam   IDLE = 16'b1111_1111_1111_1110,
             s1   = 16'b1111_1111_1111_1101,
             s2   = 16'b1111_1111_1111_1011,
             s3   = 16'b1111_1111_1111_0111,
             s4   = 16'b1111_1111_1110_1111,
             s5   = 16'b1111_1111_1101_1111,
             s6   = 16'b1111_1111_1011_1111,
             s7   = 16'b1111_1111_0111_1111,
             s8   = 16'b1111_1110_1111_1111,
             s9   = 16'b1111_1101_1111_1111,
             s10  = 16'b1111_1011_1111_1111,
             s11  = 16'b1111_0111_1111_1111,
             s12  = 16'b1110_1111_1111_1111,
             s13  = 16'b1101_1111_1111_1111, 
             s14  = 16'b1011_1111_1111_1111,
             s15  = 16'b0111_1111_1111_1111; 
reg [15:0]   state=IDLE;				 
//********************************************************
//********************************************************
reg         cs_reg       = 1'b1;
reg         sclk_reg     = 1'b0;
reg         sclk_reg2     = 1'b0;
reg         sdo_reg      = 1'b0;
reg         locked_reg   = 1'b0;
reg [15:0]  cnt_delay    = 16'd0;
reg [15:0]  cnt_count    = 16'd0;
reg [127:0] data_tr_reg  = 128'd0; 
reg [127:0] data_re_reg;
//********************************************************
//********************************************************
localparam sclk_low=16'd1;
localparam sclk_high=16'd2;
localparam read_sdi =16'd1;

always @ (posedge clk_50m)
begin
  if(!rst_n)
  begin
    state    <= IDLE;
	 cs_reg   <= 1'b1;
	 sclk_reg <= 1'b0;
	 sdo_reg  <= 1'b0;
	 cnt_delay<= 16'd0;
  end
  else
  sclk_reg2<=sclk_reg;
  case(state)
  IDLE:begin
			 cs_reg   	<= 1'b1;
			 sclk_reg 	<= 1'b0;
			 sdo_reg  	<= 1'b0;  
             cnt_delay	<= 16'd0;
			 cnt_count  <= 16'd0;
			 data_tr_reg<= data_tr;
			 
			 data_re_reg <= 128'd0;
			 locked_reg <= 1'b0;
			 state    	<= s1;			 
		 end
  s1  :begin         
          if(wr_en==1'b1)
		  begin
             state <= s2; 
			 data_tr_reg <= data_tr;
		  end
        else if(read_en==1'b1)
		  begin
             state <= s6;
				 data_tr_reg <= data_tr;
		  end
		  else
		  begin
		    state <= state;
		  end			 
       end
		 	 
  //write spi		 
  s2  :begin
         cs_reg   	<= 1'b0;
         sclk_reg 	<= 1'b0;
         sdo_reg  	<= 1'b0;	
         state       <= s3;			
       end
  s3  :begin
         sclk_reg 	<= 1'b0;
		 if(cnt_delay==16'd0)
		   sdo_reg     <= data_tr_reg[ADDR_Width+DATA_Width-1];
		 else
		   sdo_reg     <= sdo_reg;
			if(cnt_delay>sclk_low)
			begin
			  state     <= s4;
			  cnt_delay <= 16'd0;
              data_tr_reg <= data_tr_reg <<1;		  
			end
			else
			begin
			  state <= s3;
			  cnt_delay <= cnt_delay + 16'd1;
			end
	    end
	s4 :begin
         sclk_reg 	<= 1'b1;
			if(cnt_delay>sclk_high)
			begin
			  state <= s5;
			  cnt_delay <= 16'd0;				  
			end
			else
			begin
			  state <= s4;
			  cnt_delay <= cnt_delay + 16'd1;
			end
	    end
	s5 :begin
			if(cnt_count>(ADDR_Width+DATA_Width-2))
			begin
			  state     <= s14;
			  cnt_count <= 16'd0;
			  cs_reg   	<= 1'b0;
			  sclk_reg 	<= 1'b0;
			  sdo_reg   <= sdo_reg;
			end
         else
			begin
              state       <= s3;			           				  
			  cnt_count   <= cnt_count+16'd1;
			  sclk_reg 	  <= 1'b0;
         end			  
	    end
	//read spi
	s6:begin
         cs_reg   	<= 1'b0;
         sclk_reg 	<= 1'b0;
         sdo_reg  	<= 1'b0;	
         state       <= s7;            
      end	
	s7:begin
         sclk_reg 	<= 1'b0;
		 if(cnt_delay==16'd0)
		   sdo_reg     <= data_tr_reg[ADDR_Width+DATA_Width-1];
		 else
		   sdo_reg     <= sdo_reg;
			if(cnt_delay>sclk_low)
			begin
			  state     <= s8;
			  cnt_delay <= 16'd0;
              data_tr_reg<= data_tr_reg<<1;
			end
			else
			begin
			  state     <= s7;
			  cnt_delay <= cnt_delay + 16'd1;
			end         
      end
   s8:begin
            sclk_reg 	<= 1'b1;
			if(cnt_delay>sclk_high)
			begin
			  state     <= s9;
			  cnt_delay <= 16'd0;				  
			end
			else
			begin
			  state     <= s8;
			  cnt_delay <= cnt_delay + 16'd1;
			end
	   end
   s9:begin
			if(cnt_count>(ADDR_Width-2))
			begin
			  state     <= s10;
			  cnt_count <= 16'd0;
			  sclk_reg 	<= 1'b0;
			  sdo_reg   <= 1'b0;
			end
         else
			begin
           state       <= s7;
			  cnt_count   <= cnt_count+16'd1;
			  sclk_reg 	  <= 1'b0;
         end		
	   end

    //read	   
	s10:begin
         sclk_reg 	<= 1'b0;
			if(cnt_delay==read_sdi)
			  data_re_reg[DATA_Width-1:0] <= {data_re_reg[DATA_Width-2:0],sdi};
			else
			  data_re_reg <= data_re_reg;
			if(cnt_delay>sclk_low)
			begin
			  state     <= s11;
			  cnt_delay <= 16'd0;
              data_tr_reg<= data_tr_reg<<1;			  
			end
			else
			begin
			  state <= s10;
			  cnt_delay <= cnt_delay + 16'd1;
			end
      end	
	s11:begin
            sclk_reg 	<= 1'b1;
			if(cnt_delay>sclk_high)
			begin
			  state <= s12;			  
			  cnt_delay <= 16'd0;				  
			end
			else
			begin
			  state <= s11;
			  cnt_delay <= cnt_delay + 16'd1;
			end
       end	
	s12:begin
			if(cnt_count>(DATA_Width-2))
			begin
			  state     <= s14;
			  cnt_count <= 16'd0;
			  cs_reg   	<= 1'b1;
			  sclk_reg 	<= 1'b0;
			  sdo_reg   <= 1'b0;
			end
         else
			begin
           state       <= s10;			           				  
			  cnt_count   <= cnt_count+16'd1;
			  sclk_reg 	  <= 1'b0;
         end		
	    end
   //end-spi	
	s14:begin
			locked_reg  <= 1'b0;
			sdo_reg     <= 1'b0;
			cs_reg   	<= 1'b1;
			cnt_count   <= 16'd0;
			if(cnt_delay>16'd20)
			begin
			   cnt_delay   <= 16'd0;
			   state <= s15;
			end
			else
			begin
			   state       <= s14;
			   cnt_delay   <= cnt_delay + 16'd1;
			end			 
	    end
	s15:begin      
         state      <= IDLE;
         locked_reg <= 1'b1;
          cs_reg   	<= 1'b1;			
	    end
  default: begin
				  cnt_count <= 16'd0;
				  cs_reg   	<= 1'b1;
				  sclk_reg 	<= 1'b0;
				  sdo_reg   <= 1'b0;
           end	
  endcase
end

assign cs       = cs_reg;
assign sclk     = sclk_reg2;
assign sdo      = sdo_reg;
assign data_re  = data_re_reg;
assign dbg_cs   = cs_reg;
assign dbg_sclk = sclk_reg;
assign dbg_sdo  = sdo_reg;
assign dbg_sdi  = sdi;
assign locked   = locked_reg;
//********************************************************
//********************************************************
endmodule
