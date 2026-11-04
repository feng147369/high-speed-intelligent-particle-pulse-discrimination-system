`timescale 1ns/1ps
`default_nettype none
// One outstanding event. Result metadata remains stable until the next event.
module ai_event_gate(
 input wire adc_clk,ai_clk,rst_n,enable,mode_ai,peak_start,
 input wire prefilter_done,prefilter_accept,input wire [15:0] prefilter_peak,
 input wire ai_ready,wave_ready,feature_ready,wave_done,
 input wire ai_result_valid,ai_candidate,input wire [31:0] ai_event_id,
 input wire feature_valid,feature_type,input wire [15:0] feature_peak,
 output wire event_start,output reg busy,
 output reg decision_valid,decision_accept,spectrum_valid,
 output reg spectrum_type,output reg [15:0] spectrum_peak,
 output reg [31:0] busy_count,output reg id_fault);
 wire adc_rst_n,ai_rst_n;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) adc_reset(.src_arst(rst_n),.dest_clk(adc_clk),.dest_arst(adc_rst_n));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) ai_reset(.src_arst(rst_n),.dest_clk(ai_clk),.dest_arst(ai_rst_n));
 reg send_result;
 reg [32:0] result_payload;
 wire result_ack,result_arrived;
 wire [32:0] received_payload;
 always @(posedge ai_clk or negedge ai_rst_n)begin
  if(!ai_rst_n)begin send_result<=0;result_payload<=0;end
  else if(ai_result_valid)begin send_result<=1;result_payload<={ai_event_id,ai_candidate};end
  else if(result_ack)send_result<=0;
 end
 xpm_cdc_handshake #(.DEST_EXT_HSK(0),.DEST_SYNC_FF(2),.SRC_SYNC_FF(2),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1),.WIDTH(33)) result_mailbox(
 .src_clk(ai_clk),.src_in(result_payload),.src_send(send_result),.src_rcv(result_ack),
 .dest_clk(adc_clk),.dest_out(received_payload),.dest_req(result_arrived),.dest_ack(1'b0));
 reg seen,have_ai,have_feature,have_filter,filter_accept,accept_latched,type_latched;
 reg [15:0] filter_peak;
 reg [15:0] peak_latched;
 reg [31:0] sequence_id;
 assign event_start=enable && peak_start && !busy && (!mode_ai || ai_ready) && wave_ready && feature_ready;
 always @(posedge adc_clk or negedge adc_rst_n)begin
  if(!adc_rst_n)begin
   have_filter<=0;filter_accept<=0;filter_peak<=0;seen<=0;have_ai<=0;have_feature<=0;accept_latched<=0;
   type_latched<=0;peak_latched<=0;sequence_id<=0;busy<=0;
   decision_valid<=0;decision_accept<=0;spectrum_valid<=0;spectrum_type<=0;spectrum_peak<=0;
   busy_count<=0;id_fault<=0;
  end else begin
   decision_valid<=0;spectrum_valid<=0;
   if(enable && peak_start && !event_start)busy_count<=busy_count+1'b1;
   if(event_start)begin
    busy<=1;sequence_id<=sequence_id+1'b1;have_ai<=!mode_ai;accept_latched<=1;have_feature<=0;have_filter<=0;
   end
   if(result_arrived)begin
    if(busy && mode_ai)begin
     have_ai<=1;accept_latched<=received_payload[0] && (received_payload[32:1]==sequence_id);
     if(received_payload[32:1]!=sequence_id)id_fault<=1;
    end
   end
   if(busy && prefilter_done)begin have_filter<=1;filter_accept<=prefilter_accept;filter_peak<=prefilter_peak;end
   if(busy && feature_valid)begin have_feature<=1;type_latched<=feature_type;peak_latched<=feature_peak;end
   if(busy && have_ai && have_feature && have_filter)begin
    decision_valid<=1;decision_accept<=accept_latched && filter_accept;
    spectrum_valid<=accept_latched && filter_accept;spectrum_type<=type_latched;spectrum_peak<=filter_peak;
    have_ai<=!mode_ai;accept_latched<=1;have_feature<=0;have_filter<=0;
   end
   if(busy && wave_done)busy<=0;
  end
 end
endmodule
`default_nettype wire
