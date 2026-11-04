`timescale 1ns / 1ps

module JESD204B_interface_Mod
(
    // GT Reference Clock
    input          refclk_p,  // 参考时钟正
    input          refclk_n,  // 参考时钟负
    input          rx_core_clk,  // 接收核心时钟
    //*******************************************
    // Rx Ports
    //*******************************************
    input          rx_reset,  // 接收复位

    input          rx_sysref,  // 系统参考脉冲
    output         rx_sync,  // 接收同步

    input   [3:0]  rxp,  // 串行输入正
    input   [3:0]  rxn,  // 串行输入负

    output         rx_aresetn,  // 接收低有效复位

    output  [3:0]  rx_start_of_frame,  // 帧开始标志
    output  [3:0]  rx_end_of_frame,  // 帧结束标志
    output  [15:0] rx_frame_error,  // 接收帧错误

    // Rx AXI-S interface
    output         rx_tvalid,  // 接收有效
    output [127:0] rx_tdata,  // 接收数据

    // DRP Clock input
    input          drpclk,  // 配置时钟

    // AXI-Lite Control/Status
    input          s_axi_aclk,  // 总线时钟
    input          s_axi_aresetn,  // 总线复位
    input  [11:0]  s_axi_awaddr,  // 写地址
    input          s_axi_awvalid,  // 写地址有效
    output         s_axi_awready,  // 写地址就绪
    input  [31:0]  s_axi_wdata,  // 写数据
    input   [3:0]  s_axi_wstrb,  // 写字节选通
    input          s_axi_wvalid,  // 写数据有效
    output         s_axi_wready,  // 写数据就绪
    output  [1:0]  s_axi_bresp,  // 写响应
    output         s_axi_bvalid,  // 写响应有效
    input          s_axi_bready,  // 写响应就绪
    input  [11:0]  s_axi_araddr,  // 读地址
    input          s_axi_arvalid,  // 读地址有效
    output         s_axi_arready,  // 读地址就绪
    output [31:0]  s_axi_rdata,  // 读数据
    output  [1:0]  s_axi_rresp,  // 读响应
    output         s_axi_rvalid,  // 读数据有效
    input          s_axi_rready  // 读数据就绪
    
);

//*******************************************
// Wire declaration
//*******************************************
wire         refclk;
wire         txoutclk;
wire         rxoutclk;
wire         rxencommaalign_i;
wire         rx_reset_done;
wire         rx_reset_gt;
wire [31:0]  gt0_rxdata_i;
wire [3:0]   gt0_rxcharisk_i;
wire [3:0]   gt0_rxdisperr_i;
wire [3:0]   gt0_rxnotintable_i;

wire [31:0]  gt1_rxdata_i;
wire [3:0]   gt1_rxcharisk_i;
wire [3:0]   gt1_rxdisperr_i;
wire [3:0]   gt1_rxnotintable_i;

wire [31:0]  gt2_rxdata_i;
wire [3:0]   gt2_rxcharisk_i;
wire [3:0]   gt2_rxdisperr_i;
wire [3:0]   gt2_rxnotintable_i;

wire [31:0]  gt3_rxdata_i;
wire [3:0]   gt3_rxcharisk_i;
wire [3:0]   gt3_rxdisperr_i;
wire [3:0]   gt3_rxnotintable_i;

wire [31:0]  gt4_rxdata_i;
wire [3:0]   gt4_rxcharisk_i;
wire [3:0]   gt4_rxdisperr_i;
wire [3:0]   gt4_rxnotintable_i;

wire [31:0]  gt5_rxdata_i;
wire [3:0]   gt5_rxcharisk_i;
wire [3:0]   gt5_rxdisperr_i;
wire [3:0]   gt5_rxnotintable_i;

wire [31:0]  gt6_rxdata_i;
wire [3:0]   gt6_rxcharisk_i;
wire [3:0]   gt6_rxdisperr_i;
wire [3:0]   gt6_rxnotintable_i;

wire [31:0]  gt7_rxdata_i;
wire [3:0]   gt7_rxcharisk_i;
wire [3:0]   gt7_rxdisperr_i;
wire [3:0]   gt7_rxnotintable_i;

ila_jesd ila_jesd (
	.clk(rx_core_clk), // input wire clk


	.probe0(gt0_rxdata_i), // input wire [31:0]  probe0  
	.probe1(gt1_rxdata_i), // input wire [31:0]  probe1 
	.probe2(gt2_rxdata_i), // input wire [31:0]  probe2 
	.probe3(gt3_rxdata_i), // input wire [31:0]  probe3 
	.probe4(rx_sync), // input wire [0:0]  probe4 
	.probe5(rx_sysref) // input wire [0:0]  probe5
); 

// JESD receive-link diagnostic core.  The existing ila_jesd is intentionally
// left unchanged; this core concentrates the lane-0 CGS/ILAS status signals.


   IBUFDS_GTE2 #(
   .CLKCM_CFG("TRUE"),   // Refer to Transceiver User Guide
   .CLKRCV_TRST("TRUE"), // Refer to Transceiver User Guide
   .CLKSWING_CFG(2'b11)  // Refer to Transceiver User Guide
)
IBUFDS_GTE2_inst (
   .O(refclk),         // 1-bit output: Refer to Transceiver User Guide
   .ODIV2(), // 1-bit output: Refer to Transceiver User Guide
   .CEB(1'b0),     // 1-bit input: Refer to Transceiver User Guide
   .I(refclk_p),         // 1-bit input: Refer to Transceiver User Guide
   .IB(refclk_n)        // 1-bit input: Refer to Transceiver User Guide
);
//*******************************************
// JESD204 Core
//*******************************************
jesd204b_rx jesd204b_rx_inst
 (                                                      //jesd204b_rx your_instance_name (                                                        
                                                        //  .gt0_rxdata(gt0_rxdata),                  
   // Rx                                                //  .gt0_rxcharisk(gt0_rxcharisk),            
  .rx_reset               (rx_reset),                   //  .gt0_rxdisperr(gt0_rxdisperr),            
  .rx_core_clk            (rx_core_clk),                //  .gt0_rxnotintable(gt0_rxnotintable),      
                                                        //  .gt1_rxdata(gt1_rxdata),                  
  .rx_sysref              (rx_sysref),                  //  .gt1_rxcharisk(gt1_rxcharisk),            
  .rx_sync                (rx_sync),                    //  .gt1_rxdisperr(gt1_rxdisperr),            
                                                        //  .gt1_rxnotintable(gt1_rxnotintable),      
  // Ports Required for GT                              //  .gt2_rxdata(gt2_rxdata),                  
  .rx_reset_gt            (rx_reset_gt),                //  .gt2_rxcharisk(gt2_rxcharisk),            
                                                        //  .gt2_rxdisperr(gt2_rxdisperr),            
  .rxencommaalign_out    (rxencommaalign_i),            //  .gt2_rxnotintable(gt2_rxnotintable),      
  .rx_reset_done         (rx_reset_done),               //  .gt3_rxdata(gt3_rxdata),                  
                                                        //  .gt3_rxcharisk(gt3_rxcharisk),            
  // Lane 0                                             //  .gt3_rxdisperr(gt3_rxdisperr),            
  .gt0_rxdata            (gt0_rxdata_i), //in             //  .gt3_rxnotintable(gt3_rxnotintable),    
  .gt0_rxcharisk         (gt0_rxcharisk_i),  //in         //  .gt4_rxdata(gt4_rxdata),                
  .gt0_rxdisperr         (gt0_rxdisperr_i), //in          //  .gt4_rxcharisk(gt4_rxcharisk),          
  .gt0_rxnotintable      (gt0_rxnotintable_i), //in       //  .gt4_rxdisperr(gt4_rxdisperr),          
                                                        //  .gt4_rxnotintable(gt4_rxnotintable),      
    // Lane 1                                           //  .gt5_rxdata(gt5_rxdata),                  
  .gt1_rxdata            (gt1_rxdata_i),                  //  .gt5_rxcharisk(gt5_rxcharisk),          
  .gt1_rxcharisk         (gt1_rxcharisk_i),               //  .gt5_rxdisperr(gt5_rxdisperr),          
  .gt1_rxdisperr         (gt1_rxdisperr_i),               //  .gt5_rxnotintable(gt5_rxnotintable),    
  .gt1_rxnotintable      (gt1_rxnotintable_i),            //  .gt6_rxdata(gt6_rxdata),                
                                                        //  .gt6_rxcharisk(gt6_rxcharisk),            
  // Lane 2                                             //  .gt6_rxdisperr(gt6_rxdisperr),            
  .gt2_rxdata            (gt2_rxdata_i),                  //  .gt6_rxnotintable(gt6_rxnotintable),    
  .gt2_rxcharisk         (gt2_rxcharisk_i),               //  .gt7_rxdata(gt7_rxdata),                
  .gt2_rxdisperr         (gt2_rxdisperr_i),               //  .gt7_rxcharisk(gt7_rxcharisk),          
  .gt2_rxnotintable      (gt2_rxnotintable_i),            //  .gt7_rxdisperr(gt7_rxdisperr),          
                                                        //  .gt7_rxnotintable(gt7_rxnotintable),      
  // Lane 3                                             //  .rx_reset_done(rx_reset_done),            
  .gt3_rxdata            (gt3_rxdata_i),                  
  .gt3_rxcharisk         (gt3_rxcharisk_i),               //                
  .gt3_rxdisperr         (gt3_rxdisperr_i),               //              
  .gt3_rxnotintable      (gt3_rxnotintable_i),            //           
                                                                         
  // Rx AXI-S interface for each lane                   //         
  .rx_aresetn             (rx_aresetn),                 // 
                                                        //                                          
  .rx_start_of_frame      (rx_start_of_frame),          //
  .rx_end_of_frame        (rx_end_of_frame),            //
  .rx_frame_error         (rx_frame_error),             //
                                                        //
  .rx_tdata               (rx_tdata),                   //
  .rx_tvalid              (rx_tvalid),                  //
                                                        //
  // AXI-Lite Control/Status                            //
  .s_axi_aclk             (s_axi_aclk),                 // 
  .s_axi_aresetn          (s_axi_aresetn),              //
  .s_axi_awaddr           (s_axi_awaddr),               //
  .s_axi_awvalid          (s_axi_awvalid),              //
  .s_axi_awready          (s_axi_awready),              //
  .s_axi_wdata            (s_axi_wdata),                //
  .s_axi_wstrb            (s_axi_wstrb),                //
  .s_axi_wvalid           (s_axi_wvalid),               //
  .s_axi_wready           (s_axi_wready),               //
  .s_axi_bresp            (s_axi_bresp),                //
  .s_axi_bvalid           (s_axi_bvalid),               //
  .s_axi_bready           (s_axi_bready),               //
  .s_axi_araddr           (s_axi_araddr),               //
  .s_axi_arvalid          (s_axi_arvalid),              //
  .s_axi_arready          (s_axi_arready),              //
  .s_axi_rdata            (s_axi_rdata),                //
  .s_axi_rresp            (s_axi_rresp),                //
  .s_axi_rvalid           (s_axi_rvalid),               //
  .s_axi_rready           (s_axi_rready)                //
);                                                      //
                                                        //
//------------------------------------------------------------
// Instantiate the JESD204 PHY core
//------------------------------------------------------------
jesd204b_phy_rx jesd204b_phy_rx_inst 
(
  .qpll_refclk              (refclk),            // input wire cpll_refclk
  .drpclk                   (drpclk),                      // input wire drpclk 100M
  
  .tx_reset_gt              (rx_reset_gt),            // input wire tx_reset_gt
  .rx_reset_gt              (rx_reset_gt),            // input wire rx_reset_gt
  .tx_sys_reset             (rx_reset),          // input wire tx_sys_reset
  .rx_sys_reset             (rx_reset),          // input wire rx_sys_reset
  
  .txp_out                  (),                    // output wire [2 : 0] txp_out
  .txn_out                  (),                    // output wire [2 : 0] txn_out
  .rxp_in                   (rxp),                      // input wire [2 : 0] rxp_in
  .rxn_in                   (rxn),                      // input wire [2 : 0] rxn_in
  
  .tx_core_clk              (rx_core_clk),            // input wire tx_core_clk
  .rx_core_clk              (rx_core_clk),            // input wire rx_core_clk
  .txoutclk                 (txoutclk),                  // output wire txoutclk
  .rxoutclk                 (rxoutclk),                  // output wire rxoutclk
  
  .gt_prbssel               (3'b000),              // input wire [2 : 0] gt_prbssel
  
  .gt0_txdata               (32'b0),              // input wire [31 : 0] gt0_txdata
  .gt0_txcharisk            (4'b0),        // input wire [3 : 0] gt0_txcharisk
  
  .gt1_txdata               (32'b0),              // input wire [31 : 0] gt1_txdata
  .gt1_txcharisk            (4'b0),        // input wire [3 : 0] gt1_txcharisk
  
 .gt2_txdata               (32'b0),              // input wire [31 : 0] gt2_txdata
 .gt2_txcharisk            (4'b0),        // input wire [3 : 0] gt2_txcharisk
  
 .gt3_txdata               (32'b0),              // input wire [31 : 0] gt2_txdata
 .gt3_txcharisk            (4'b0),        // input wire [3 : 0] gt2_txcharisk

  
  .tx_reset_done            ( ),        // output wire tx_reset_done
  
  .gt0_rxdata               (gt0_rxdata_i),              // output wire [31 : 0] gt0_rxdata
  .gt0_rxcharisk            (gt0_rxcharisk_i),        // output wire [3 : 0] gt0_rxcharisk 
  .gt0_rxdisperr            (gt0_rxdisperr_i),        // output wire [3 : 0] gt0_rxdisperr
  .gt0_rxnotintable         (gt0_rxnotintable_i),  // output wire [3 : 0] gt0_rxnotintable
  
  .gt1_rxdata               (gt1_rxdata_i),              // output wire [31 : 0] gt1_rxdata
  .gt1_rxcharisk            (gt1_rxcharisk_i),        // output wire [3 : 0] gt1_rxcharisk
  .gt1_rxdisperr            (gt1_rxdisperr_i),        // output wire [3 : 0] gt1_rxdisperr
  .gt1_rxnotintable         (gt1_rxnotintable_i),  // output wire [3 : 0] gt1_rxnotintable
  
 .gt2_rxdata               (gt2_rxdata_i),              // output wire [31 : 0] gt2_rxdata
 .gt2_rxcharisk            (gt2_rxcharisk_i),        // output wire [3 : 0] gt2_rxcharisk
 .gt2_rxdisperr            (gt2_rxdisperr_i),        // output wire [3 : 0] gt2_rxdisperr
 .gt2_rxnotintable         (gt2_rxnotintable_i),  // output wire [3 : 0] gt2_rxnotintable

 .gt3_rxdata               (gt3_rxdata_i),              // output wire [31 : 0] gt2_rxdata
 .gt3_rxcharisk            (gt3_rxcharisk_i),        // output wire [3 : 0] gt2_rxcharisk
 .gt3_rxdisperr            (gt3_rxdisperr_i),        // output wire [3 : 0] gt2_rxdisperr
 .gt3_rxnotintable         (gt3_rxnotintable_i),  // output wire [3 : 0] gt2_rxnotintable
  
  .rx_reset_done            (rx_reset_done),        // output wire rx_reset_done
  
  .rxencommaalign           (rxencommaalign_i),      // input wire rxencommaalign
  .common0_qpll_clk_out(),        // output wire common0_qpll_clk_out
  .common0_qpll_refclk_out(),  // output wire common0_qpll_refclk_out
  .common0_qpll_lock_out()      // output wire common0_qpll_lock_out  
);
endmodule
