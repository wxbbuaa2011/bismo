# Copyright (c) 2018 Norwegian University of Science and Technology (NTNU)
#
# BSD v3 License
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of [project] nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# target frequency for Vivado FPGA synthesis
FREQ_MHZ ?= 150.0
# controls whether Vivado will run in command-line or GUI mode
VIVADO_MODE ?= batch # or gui
# which C++ compiler to use
CC = g++
# scp/rsync target to copy files to board
PLATFORM ?= PYNQZ1
URI = $($(PLATFORM)_URI)
# overlay dims
M ?= 8
K ?= 256
N ?= 8
OVERLAY_CFG = $(M)x$(K)x$(N)

# other project settings
SBT ?= sbt
SBT_FLAGS ?= -Dsbt.log.noformat=true
# internal build dirs and names for the Makefile
TOP ?= $(shell readlink -f .)
TIDBITS_ROOT ?= $(TOP)/fpga-tidbits
TIDBITS_REGDRV_ROOT ?= $(TIDBITS_ROOT)/src/main/resources/cpp/platform-wrapper-regdriver
export OHMYXILINX := $(TOP)/oh-my-xilinx
export PATH := $(PATH):$(OHMYXILINX)
BUILD_DIR ?= $(TOP)/build/$(OVERLAY_CFG)
BUILD_DIR_CHARACTERIZE := $(BUILD_DIR)/characterize
BUILD_DIR_DEPLOY := $(BUILD_DIR)/deploy
BUILD_DIR_VERILOG := $(BUILD_DIR)/hw/verilog
BUILD_DIR_EMU := $(BUILD_DIR)/emu
BUILD_DIR_HWDRV := $(BUILD_DIR)/hw/driver
BUILD_DIR_EMULIB_CPP := $(BUILD_DIR)/hw/cpp_emulib
VERILOG_SRC_DIR := $(TOP)/src/main/verilog
APP_SRC_DIR := $(TOP)/src/main/cpp/app
VIVADO_IN_PATH := $(shell command -v vivado 2> /dev/null)
ZSH_IN_PATH := $(shell command -v zsh 2> /dev/null)
CPPTEST_SRC_DIR := $(TOP)/src/test/cosim
HW_VERILOG := $(BUILD_DIR_VERILOG)/$(PLATFORM)Wrapper.v
PLATFORM_SCRIPT_DIR := $(TOP)/src/main/script/$(PLATFORM)/target

# platform-specific Makefile include for bitfile synthesis
include platforms/$(PLATFORM).mk

# note that all targets are phony targets, no proper dependency tracking
.PHONY: hw_verilog emulib hw_driver hw_vivadoproj bitfile hw sw all rsync test
.PHONY: resmodel characterize check_vivado

check_vivado:
ifndef VIVADO_IN_PATH
    $(error "vivado not found in path")
endif

check_zsh:
ifndef ZSH_IN_PATH
    $(error "zsh not in path; needed by oh-my-xilinx for characterization")
endif

# run Scala/Chisel tests
Test%:
	$(SBT) $(SBT_FLAGS) "test-only $@"

# run hardware-software cosimulation tests
EmuTest%:
	mkdir -p $(BUILD_DIR)/$@; $(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain $@ $(BUILD_DIR)/$@"; cp -r $(CPPTEST_SRC_DIR)/$@.cpp $(BUILD_DIR)/$@; cd $(BUILD_DIR)/$@; g++ -std=c++11 *.cpp driver.a -o $@; ./$@

# generate cycle-accurate C++ emulator driver lib
$(BUILD_DIR_EMU)/driver.a:
	mkdir -p $(BUILD_DIR_EMU); $(SBT) $(SBT_FLAGS) "runMain bismo.EmuLibMain main $(BUILD_DIR_EMU)"

# generate emulator executable including software sources
emu: $(BUILD_DIR_EMU)/driver.a
	cp -r $(APP_SRC_DIR)/* $(BUILD_DIR_EMU)/; cd $(BUILD_DIR_EMU); g++ -std=c++11 *.cpp driver.a -o emu; ./emu

# run resource/Fmax characterization
Characterize%:
	mkdir -p $(BUILD_DIR)/$@; cp $(VERILOG_SRC_DIR)/*.v $(BUILD_DIR)/$@; $(SBT) $(SBT_FLAGS) "runMain bismo.CharacterizeMain $@ $(BUILD_DIR)/$@ $(PLATFORM)"

# generate register driver for the Chisel accelerator
hw_driver: $(BUILD_DIR_HWDRV)/BitSerialMatMulAccel.hpp

$(BUILD_DIR_HWDRV)/BitSerialMatMulAccel.hpp:
	mkdir -p "$(BUILD_DIR_HWDRV)"; $(SBT) $(SBT_FLAGS) "runMain bismo.DriverMain $(PLATFORM) $(BUILD_DIR_HWDRV) $(TIDBITS_REGDRV_ROOT)"

# generate Verilog for the Chisel accelerator
hw_verilog: $(HW_VERILOG)

$(HW_VERILOG):
	$(SBT) $(SBT_FLAGS) "runMain bismo.ChiselMain $(PLATFORM) $(BUILD_DIR_VERILOG) $M $K $N"

resmodel:
	$(SBT) $(SBT_FLAGS) "runMain bismo.ResModelMain $(PLATFORM) $(BUILD_DIR_VERILOG) $M $K $N"

# copy scripts to the deployment folder
script:
	cp $(PLATFORM_SCRIPT_DIR)/* $(BUILD_DIR_DEPLOY)/

# get everything ready to copy onto the platform and create a deployment folder
all: hw sw script

# use rsync to synchronize contents of the deployment folder onto the platform
rsync:
	rsync -avz $(BUILD_DIR_DEPLOY) $(URI)

# remove everything that is built
clean:
	rm -rf $(BUILD_DIR)
