VERILATOR_SRC_DIR = /usr/share/verilator/include

$(BUILD_DIR_DEPLOY)/verilog/verilated: $(HW_TO_SYNTH)
	mkdir -p $(BUILD_DIR_DEPLOY)/verilog; \
	cp -rf $(BUILD_DIR_VERILOG)/* $(BUILD_DIR_DEPLOY)/verilog; \
	cp -rf $(VERILOG_SRC_DIR)/* $(BUILD_DIR_DEPLOY)/verilog; \
	cd $(BUILD_DIR_DEPLOY)/verilog; \
	verilator -Iother-verilog --cc TesterWrapper.v -Wno-assignin -Wno-fatal -Wno-lint -Wno-style -Wno-COMBDLY -Wno-STMTDLY --Mdir verilated --trace; \
	cp -rf $(VERILATOR_SRC_DIR)/verilated.cpp $(BUILD_DIR_DEPLOY)/verilog/verilated; \
	cp -rf $(VERILATOR_SRC_DIR)/verilated_vcd_c.cpp $(BUILD_DIR_DEPLOY)/verilog/verilated;

hw: $(BUILD_DIR_DEPLOY)/verilog/verilated

# copy all user sources and driver sources to the deployment folder
sw: $(BUILD_DIR_HWDRV)/$(HW_SW_DRIVER)
	mkdir -p $(BUILD_DIR_DEPLOY); \
	mkdir -p $(BUILD_DIR_DEPLOY)/driver; \
	mkdir -p $(BUILD_DIR_DEPLOY)/test; \
	mkdir -p $(BUILD_DIR_DEPLOY)/inflib; \
	mkdir -p $(BUILD_DIR_DEPLOY)/hls_include; \
	cp -rf $(BUILD_DIR_HWDRV)/* $(BUILD_DIR_DEPLOY)/driver/; \
	cp -rf $(APP_SRC_DIR)/* $(BUILD_DIR_DEPLOY)/test/;
	cp -rf $(INFLIB_SRC_DIR)/* $(BUILD_DIR_DEPLOY)/inflib; \
	cp -rf $(HLS_SIM_INCL)/* $(BUILD_DIR_DEPLOY)/hls_include;

emu: inflib_emu
	cd $(BUILD_DIR_DEPLOY); \
	sh compile_testapp.sh; \
	LD_LIBRARY_PATH=$(BUILD_DIR_DEPLOY) ./testapp t;

$(BUILD_DIR_DEPLOY)/libbismo_inference.so: hw sw script
	cd $(BUILD_DIR_DEPLOY); \
	sh compile_inflib.sh;

inflib_emu: $(BUILD_DIR_DEPLOY)/libbismo_inference.so

# hw-sw cosimulation tests with extra HLS dependencies
EmuTestVerifyHLSInstrEncoding:
	mkdir -p $(BUILD_DIR)/$@; \
	$(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain $@ $(BUILD_DIR)/$@ verilator $(DEBUG_CHISEL)"; \
	cp -rf $(CPPTEST_SRC_DIR)/$@.cpp $(BUILD_DIR)/$@; \
	ln -s $(INFLIB_SRC_DIR)/BISMOInstruction.* $(BUILD_DIR)/$@/; \
	cd $(BUILD_DIR)/$@; sh verilator-build.sh -I$(HLS_SIM_INCL); ./VerilatedTesterWrapper

#BUILD_DIR_EMU := $(BUILD_DIR)/emu
#BUILD_DIR_EMULIB_CPP := $(BUILD_DIR)/hw/cpp_emulib
#
#
#EmuTestExecInstrGen:
#	mkdir -p $(BUILD_DIR)/$@;
#	$(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain $@ $(BUILD_DIR)/$@ verilator $(DEBUG_CHISEL)";
#	cp -rf $(CPPTEST_SRC_DIR)/$@.cpp $(BUILD_DIR)/$@;
#	ln -s $(INFLIB_SRC_DIR)/*.hpp $(BUILD_DIR)/$@;
#	ln -s $(APP_SRC_DIR)/gemmbitserial $(BUILD_DIR)/$@;
#	cd $(BUILD_DIR)/$@; sh verilator-build.sh -I$(HLS_SIM_INCL); ./VerilatedTesterWrapper
#
#EmuTestFetchInstrGen:
#	mkdir -p $(BUILD_DIR)/$@;
#	$(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain $@ $(BUILD_DIR)/$@ verilator $(DEBUG_CHISEL)";
#	cp -rf $(CPPTEST_SRC_DIR)/$@.cpp $(BUILD_DIR)/$@;
#	ln -s $(INFLIB_SRC_DIR)/*.hpp $(BUILD_DIR)/$@;
#	ln -s $(APP_SRC_DIR)/gemmbitserial $(BUILD_DIR)/$@;
#	cd $(BUILD_DIR)/$@; sh verilator-build.sh -I$(HLS_SIM_INCL); ./VerilatedTesterWrapper
#
#
## run hardware-software cosimulation tests
#EmuTest%:
#	mkdir -p $(BUILD_DIR)/$@; $(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain $@ $(BUILD_DIR)/$@ cpp $(DEBUG_CHISEL)"; cp -r $(CPPTEST_SRC_DIR)/$@.cpp $(BUILD_DIR)/$@; cp -r $(APP_SRC_DIR)/gemmbitserial $(BUILD_DIR)/$@; cd $(BUILD_DIR)/$@; g++ -std=c++11 *.cpp driver.a -o $@; ./$@
#
## run hardware-software cosimulation tests (in debug mode with waveform dump)
#DebugEmuTest%:
#	mkdir -p $(BUILD_DIR)/$@; $(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain EmuTest$* $(BUILD_DIR)/$@ cpp 1"; cp -r $(CPPTEST_SRC_DIR)/EmuTest$*.cpp $(BUILD_DIR)/$@; cp -r $(APP_SRC_DIR)/gemmbitserial $(BUILD_DIR)/$@; cd $(BUILD_DIR)/$@; g++ -std=c++11 -DDEBUG *.cpp driver.a -o $@; ./$@
#
## generate emulator executable including software sources
#emu: $(BUILD_DIR_EMU)/verilator-build.sh
#	cp -rf $(APP_SRC_DIR)/* $(BUILD_DIR_EMU)/;
#	cp -rf $(INFLIB_SRC_DIR)/* $(BUILD_DIR_EMU)/; \
#	cd $(BUILD_DIR_EMU); sh verilator-build.sh -I$(HLS_SIM_INCL); mv VerilatedTesterWrapper emu; ./emu t
#
## generate cycle-accurate C++ emulator for the whole system via Verilator
#$(BUILD_DIR_EMU)/verilator-build.sh: $(BUILD_DIR_VERILOG)/ExecInstrGen.v
#	mkdir -p $(BUILD_DIR_EMU); \
#	$(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain main $(BUILD_DIR_EMU) verilator $(DEBUG_CHISEL)"; \
#	cp -rf $(BUILD_DIR_VERILOG)/* $(BUILD_DIR_EMU)/
#
#
#
## generate dynamic lib for inference, emulated hardware
#inflib_emu: $(BUILD_DIR_EMU)/verilator-build.sh
#	rm -rf $(BUILD_DIR_INFLIB); \
#	mkdir -p $(BUILD_DIR_INFLIB); \
#	cp -rf $(BUILD_DIR_EMU)/* $(BUILD_DIR_INFLIB)/; \
#	cp -rf $(INFLIB_SRC_DIR)/* $(BUILD_DIR_INFLIB)/; \
#	cd $(BUILD_DIR_INFLIB); \
#	verilator -Iother-verilog --cc TesterWrapper.v -Wno-assignin -Wno-fatal -Wno-lint -Wno-style -Wno-COMBDLY -Wno-STMTDLY --Mdir verilated --trace; \
#	cp -rf $(VERILATOR_SRC_DIR)/verilated.cpp .; \
#	cp -rf $(VERILATOR_SRC_DIR)/verilated_vcd_c.cpp .; \
#	g++ -std=c++11 -I$(HLS_SIM_INCL) -I$(BUILD_DIR_EMU) -Iverilated -I$(VERILATOR_SRC_DIR) -I$(APP_SRC_DIR) -fPIC verilated/*.cpp *.cpp -shared -o $(BUILD_DIR_INFLIB)/libbismo_inference.so

#