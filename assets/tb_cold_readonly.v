`timescale 1ns/1ps
module ila_adc_spi(input clk,
 input [7:0] probe0,probe1,probe2,probe3,probe4,probe5,probe6,probe7,
 input [7:0] probe8,probe9,probe10,probe11,
 input [1:0] probe12,input [7:0] probe13,probe14,input [5:0] probe15);
endmodule

module tb_cold_readonly;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 wire cs,sclk,sdo,oe,config_ok;
 tri sdio;
 reg adc_oe=0,adc_data=0;
 assign sdio=oe?sdo:1'bz;
 assign sdio=adc_oe?adc_data:1'bz;
 AD9694_Configure_Mod uut(.clk_50m(clk),.rst_n(rst_n),.spi_rst_p(),
  .spi_cs(cs),.spi_sclk(sclk),.spi_sdo(sdo),.spi_oe(oe),
  .spi_sdi(sdio),.SPI_config_OK(config_ok));
 integer fixture=0,edges=0,frames=0;
 reg active=0;
 reg [15:0] instruction=0;
 reg [7:0] response=0,model_id,model_mode;
 initial begin
  if(!$value$plusargs("CASE=%d",fixture))fixture=0;
  #1;model_id=8'hDC;model_mode=8'h07;
  if(fixture==1)begin model_id=8'hDB;model_mode=0;end
  if(fixture==2)model_mode=8'h08;
  #200;rst_n=1;
  wait(uut.por_done===1);
  #100;
  if(uut.por_fault!==0 || uut.por_flags!==8'h3D ||
     uut.por_repeat_ok!==3 || uut.por_step!==3)
   $fatal(1,"Read-only completion checks failed");
  if(uut.por_chip_id!==model_id || uut.por_chip_id_repeat!==model_id ||
     uut.por_mode!==model_mode || uut.por_mode_repeat!==model_mode ||
     uut.por_id_frame!=={16'h8004,model_id} ||
     uut.por_mode_frame!=={16'h8200,model_mode} ||
     uut.por_id_mid!==model_id || uut.por_mode_mid!==model_mode)
   $fatal(1,"Initial register snapshot/raw frame/middle sampling mismatch");
  if(frames!=4 || cs!==1 || sclk!==0 || oe!==0 || config_ok!==0)
   $fatal(1,"Expected four reads, idle bus, acquisition disabled");
  #1000000;
  if(frames!=4 || model_mode!==((fixture==0)?8'h07:(fixture==1)?8'h00:8'h08))
   $fatal(1,"Snapshot image did not remain read-only and idle: fixture=%0d frames=%0d mode=%h expected=%h",fixture,frames,model_mode,((fixture==0)?8'h07:(fixture==1)?8'h00:8'h08));
  $display("PASS CASE=%0d: initial ID=%h MODE=%h preserved; exactly four read frames; no reset/index/config writes; raw frames and mid sampling agree; flags=3D; bus remains idle",fixture,model_id,model_mode);
  $finish;
 end
 initial begin #50000000;$fatal(1,"Timeout");end
 always @(negedge cs) begin
  if(rst_n && $time<20000000)$fatal(1,"SPI started before startup settling wait");
  active=1;edges=0;instruction=0;adc_oe=0;
 end
 always @(posedge sclk) if(!cs)begin
  edges=edges+1;
  if(edges<=16)begin
   if(oe!==1 || (sdio!==0 && sdio!==1))$fatal(1,"Instruction drive invalid");
   instruction={instruction[14:0],sdio};
   if(edges==16)begin
    if(instruction!==((frames%2==0)?16'h8004:16'h8200))
     $fatal(1,"Unexpected transaction or WRITE: %h",instruction);
    response=(instruction==16'h8004)?model_id:model_mode;
   end
  end else begin
   if(oe!==0 || adc_oe!==1 || sdio!==response[24-edges])
    $fatal(1,"Read turnaround/data mismatch");
  end
 end
 always @(negedge sclk)begin
  if(!cs && edges>=16 && edges<24)begin
   if(oe!==0)$fatal(1,"SDIO not released");
   adc_oe=1;adc_data=response[23-edges];
  end else adc_oe=0;
 end
 always @(posedge cs)if(active)begin
  if(edges!=24)$fatal(1,"Wrong frame length");
  active=0;frames=frames+1;adc_oe=0;
 end
endmodule
