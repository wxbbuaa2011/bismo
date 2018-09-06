
SDACCEL_DSA ?= xilinx_kcu1500_dynamic_5_0
SDACCEL_OPTIMIZE ?= 3
SDACCEL_SLR ?= SLR0

SDACCEL_XML := $(TIDBITS_ROOT)/src/main/resources/xml/kernel_GenericSDAccelWrapperTop.xml
SDACCEL_XO := $(BUILD_DIR)/hw/bismo.xo
SDACCEL_XO_SCRIPT := $(TIDBITS_ROOT)/src/main/resources/script/gen_xo.tcl
SDACCEL_XCLBIN := $(BUILD_DIR)/hw/bismo.xclbin
SDACCEL_IP_SCRIPT := $(TIDBITS_ROOT)/src/main/resources/script/package_ip.tcl
SDACCEL_IP := $(BUILD_DIR)/hw/ip
SDACCEL_IMPL_DIR := $(BUILD_DIR)/hw/_xocc_link_bismo_bismo.dir/_vpl/ipi/imp/imp.runs/impl_1
SDACCEL_SLR_TCL := $(BUILD_DIR)/hw/userPostSysLink.tcl
SDACCEL_INSTNAME := GenericSDAccelWrapperTop_1
EXTRA_HDL := $(BUILD_DIR_VERILOG)/GenericSDAccelWrapperTop.v
SDX_ENVVAR_SET := $(ls ${XILINX_SDX} 2> /dev/null)
RUN_APP :=  $(BUILD_DIR_DEPLOY)/bismo

.PHONY: sdaccelip xo xclbin check_sdx

check_sdx:
ifndef XILINX_SDX
    $(error "SDAccel environment variable XILINX_SDX not set properly")
endif

xo: $(SDACCEL_XO)
xclbin: $(SDACCEL_XCLBIN)
sdaccelip: $(SDACCEL_IP)

# TODO .v files should be platform-specific, ideally generated by fpga-tidbits
# for now we just copy everything from the fpga-tidbits extra verilog dir
$(EXTRA_HDL):
	cp $(TIDBITS_ROOT)/src/main/resources/verilog/*.v $(BUILD_DIR_VERILOG); cp src/main/vhdl/*.vhd $(BUILD_DIR_VERILOG)

$(SDACCEL_IP): $(HW_VERILOG) $(EXTRA_HDL)
	cd $(BUILD_DIR)/hw; vivado -mode batch -source $(SDACCEL_IP_SCRIPT) -tclargs GenericSDAccelWrapperTop $(BUILD_DIR_VERILOG) $(SDACCEL_IP)

$(SDACCEL_XO): $(SDACCEL_IP)
	cd $(BUILD_DIR)/hw; vivado -mode batch -source $(SDACCEL_XO_SCRIPT) -tclargs $(SDACCEL_XO) GenericSDAccelWrapperTop $(SDACCEL_IP) $(SDACCEL_XML)

$(SDACCEL_SLR_TCL):
	echo "set_property CONFIG.SLR_ASSIGNMENTS $(SDACCEL_SLR) [get_bd_cells $(SDACCEL_INSTNAME)]" > $(SDACCEL_SLR_TCL)

$(SDACCEL_XCLBIN): $(SDACCEL_XO) $(SDACCEL_SLR_TCL)
	cd $(BUILD_DIR)/hw; xocc --link --xp param:compiler.userPostSysLinkTcl=$(SDACCEL_SLR_TCL) --report system --save-temps --target hw --kernel_frequency "0:$(FREQ_MHZ)|1:$(FREQ_MHZ)" --optimize $(SDACCEL_OPTIMIZE) --platform $(SDACCEL_DSA) $(SDACCEL_XO) -o $(SDACCEL_XCLBIN)

hw: $(SDACCEL_XCLBIN)
	mkdir -p $(BUILD_DIR_DEPLOY); cp $(SDACCEL_XCLBIN) $(BUILD_DIR_DEPLOY)/BitSerialMatMulAccel

sw: $(RUN_APP)

$(RUN_APP): $(BUILD_DIR_HWDRV)/BitSerialMatMulAccel.hpp
	mkdir -p $(BUILD_DIR_DEPLOY); cp -r $(APP_SRC_DIR)/* $(BUILD_DIR_DEPLOY)/; cp $(BUILD_DIR_HWDRV)/* $(BUILD_DIR_DEPLOY)/;
	cd $(BUILD_DIR_DEPLOY)/;
	g++ -std=c++11 -DCSR_BASE_ADDR=0x1800000  -DFCLK_MHZ=$(FREQ_MHZ) -I$(XILINX_SDX)/runtime/driver/include  -L$(XILINX_SDX)/platforms/$(SDACCEL_DSA)/sw/driver/gem -L$(XILINX_SDX)/runtime/lib/x86_64 -lxilinxopencl -lxclgemdrv -lpthread -lrt -lstdc++ $(BUILD_DIR_DEPLOY)/*.cpp -o $(BUILD_DIR_DEPLOY)/bismo

report: $(SDACCEL_XCLBIN)
	cat $(SDACCEL_IMPL_DIR)/updated_full_design_utilization_placed.rpt | grep "CLB LUTs" -B 3 -A 15
	cat $(SDACCEL_IMPL_DIR)/updated_full_design_utilization_placed.rpt | grep "RAMB36/FIFO" -B 4 -A 4
	cat $(SDACCEL_IMPL_DIR)/updated_full_design_utilization_placed.rpt | grep "DSP48E2 only" -B 4 -A 1
	cat $(SDACCEL_IMPL_DIR)/updated_full_design_utilization_placed.rpt | grep "SLR Index |  CLBs" -B 1 -A 7
	cat $(SDACCEL_IMPL_DIR)/updated_full_design_timing_summary_routed.rpt | grep "Design Timing Summary" -B 1 -A 10
	
run: $(RUN_APP)
	cd $(BUILD_DIR_DEPLOY); LD_LIBRARY_PATH=$(LD_LIBRARY_PATH):$(XILINX_SDX)/runtime/lib/x86_64:$(XILINX_SDX)/platforms/$(SDACCEL_DSA)/sw/driver/gem $(BUILD_DIR_DEPLOY)/bismo
