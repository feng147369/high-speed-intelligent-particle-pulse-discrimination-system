`timescale 1ns/1ps
`default_nettype none
// 500 MSPS, two consecutive samples per 250 MHz cycle. No decimation.
// Legacy physical windows: skip 100 ns, evaluate 1 us, dead time 20 us.
module findpeak_tritium #(
 parameter integer SKIP_SAMPLES=50,EVAL_SAMPLES=500,MIN_HIGH_SAMPLES=15,
 parameter integer DEAD_CLOCKS=5000,RECOVERY_CLOCKS=80,INIT_CLOCKS=25000000
)(
input wire clk,rst_n,enable,data_valid,baseline_valid,
 input wire [15:0] data0,data1,baseline,threshold,
 output reg baseline_enable,early,accepted,decision_valid,
 output reg [15:0] peak,output wire [15:0] critical,output wire [4:0] state_debug);
 localparam IDLE=0,EVALUATE=1,DEAD=2,RECOVER=3,FINALIZE=4;
 reg [2:0] state;
 reg [24:0] init_count;
 reg [12:0] hold_count;
 reg [9:0] index,high_count;
 reg [15:0] event_base,event_level,max_raw;
 wire [16:0] level_sum={1'b0,baseline}+{1'b0,threshold};
 reg [15:0] critical_s,data0_s,data1_s,baseline_s;
 reg valid_s,enable_s,baseline_valid_s;
 always @(posedge clk)begin
  if(!rst_n)begin critical_s<=16'hffff;data0_s<=0;data1_s<=0;baseline_s<=0;valid_s<=0;enable_s<=0;baseline_valid_s<=0;end
  else begin critical_s<=level_sum[16]?16'hffff:level_sum[15:0];data0_s<=data0;data1_s<=data1;baseline_s<=baseline;valid_s<=data_valid;enable_s<=enable;baseline_valid_s<=baseline_valid;end
 end
 assign critical=critical_s;
 assign state_debug=(state==IDLE)?5'b00001:(state==EVALUATE)?5'b00010:(state==DEAD)?5'b01000:5'b10000;
 wire [1:0] hits=((index>=SKIP_SAMPLES && index<EVAL_SAMPLES && data0_s>=event_level)?2'd1:2'd0)+
                 ((index+1>=SKIP_SAMPLES && index+1<EVAL_SAMPLES && data1_s>=event_level)?2'd1:2'd0);
 wire [10:0] high_next={1'b0,high_count}+hits;
 wire [15:0] pair_max=(index+1<EVAL_SAMPLES && data1_s>data0_s)?data1_s:data0_s;
 wire [15:0] max1=(pair_max>max_raw)?pair_max:max_raw;
 wire [16:0] peak_delta={1'b0,max_raw}-{1'b0,event_base};
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;init_count<=0;hold_count<=0;index<=0;high_count<=0;
   event_base<=0;event_level<=0;max_raw<=0;peak<=0;baseline_enable<=1;early<=0;accepted<=0;decision_valid<=0;
  end else begin
   early<=0;accepted<=0;decision_valid<=0;
   if(init_count<INIT_CLOCKS)init_count<=init_count+1'b1;
   case(state)
    IDLE:begin
     baseline_enable<=1;
     if(enable_s && valid_s && baseline_valid_s && init_count>=INIT_CLOCKS)begin
      if(data0_s>=critical || data1_s>=critical)begin
       baseline_enable<=0;early<=1;event_base<=baseline_s;event_level<=critical;high_count<=0;
       if(data0_s>=critical)begin index<=2;max_raw<=(data0_s>data1_s)?data0_s:data1_s;end
       else begin index<=1;max_raw<=data1_s;end
       state<=EVALUATE;
      end
     end
    end
    EVALUATE:begin
     if(!valid_s)begin decision_valid<=1;baseline_enable<=1;hold_count<=0;state<=RECOVER;end
     else begin
      max_raw<=max1;high_count<=high_next[9:0];index<=index+2;
      if(index+2>=EVAL_SAMPLES)begin
       state<=FINALIZE;
      end
     end
    end
    FINALIZE:begin
     decision_valid<=1;peak<=peak_delta[16]?16'd0:peak_delta[15:0];hold_count<=0;
     if(high_count>=MIN_HIGH_SAMPLES)begin accepted<=1;state<=DEAD;end
     else begin baseline_enable<=1;state<=RECOVER;end
    end
    DEAD:if(hold_count>=DEAD_CLOCKS-1)begin hold_count<=0;baseline_enable<=1;state<=RECOVER;end
         else hold_count<=hold_count+1'b1;
    RECOVER:if(hold_count>=RECOVERY_CLOCKS-1)begin hold_count<=0;state<=IDLE;end
            else hold_count<=hold_count+1'b1;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`default_nettype wire
