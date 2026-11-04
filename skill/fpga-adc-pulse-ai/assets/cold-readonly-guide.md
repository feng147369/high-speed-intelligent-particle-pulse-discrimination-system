# 上电只读参考RTL

本文件夹包含历史已验证的Configure诊断模块和协议测试平台。它们来自本案例，不是跨板卡通用驱动。

前提：顶层对SDIO使用IOBUF；Configure输入实际100MHz（端口旧名clk_50m）；rst_n由LMK完成信号提供；已有ila_adc_spi IP，16个probe位宽为12×8、2、8、8、6。

诊断模块只有四帧读：0004、0200、0004、0200，前面等待20ms。不写软复位、pair或配置；SPI_config_OK恒0，正常采样故意暂停。此版不能代替正常采集初始化。

在适配工程前备份原Configure，保持同名模块只有一份。依赖和接口匹配后生成新bit与对应ltx。确认ADC物理冷上电且此前没有其他程序写入，再下载此诊断版；只重下载FPGA不足以保证ADC默认值。ILA抓锁存值无需抢上电瞬间。

probe0/1：ID和mode；2/3：重复值；4/5：ID指令80/04；6/7：mode指令82/00；8/9：被动观察数据；10/11：中段采样；12：重复校验，正常3；13：协议状态，正常3D；14：总线监视；15：step，完成03。主机、被动和中段值应相符，但共享输入不能替代外部仪器。

AD9694官方指纹DB/00，AD6684为DC/07；状态通过不代表已经证明物理冷上电或实物来源。测试完恢复原Configure并重新生成正常bit/ltx。

历史仿真使用Vivado2022.1，模型分别提供DC/07、DB/00和DC/08。可在独立可写目录编译参考RTL与tb_cold_readonly.v，展开tb_cold_readonly，再以CASE=0/1/2运行。xsim.bat的plusarg建议写入参数文件，避免Windows批处理对等号的解析问题。该测试平台已有ILA空壳，仅用于协议仿真，不能加入实板Sources替代ILA IP。

历史PASS节选在references/evidence/historical-rtl-results.json；本次技能打包没有重新跑RTL仿真或用户完整工程实现。
