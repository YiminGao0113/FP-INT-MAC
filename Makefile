# Flexible Makefile for compiling Verilog code with Icarus Verilog and viewing with GTKWave

# Directory for output files
BUILD_DIR := build
SRC_DIR := src
TB_DIR := tb

# Phony targets
.PHONY: all clean fp_int_mac $(MAKECMDGOALS)

# Default target
all: fp_int_mac

# Rule to compile fp_int_mac with dependencies when running `make all`
fp_int_mac:
	@echo "Processing fp_int_mac..."
	@mkdir -p $(BUILD_DIR)
	iverilog -o $(BUILD_DIR)/fp_int_mac_dsn $(TB_DIR)/fp_int_mac_tb.v $(SRC_DIR)/fp_int_mac.v $(SRC_DIR)/fp_int_mul.v $(SRC_DIR)/fp_int_acc.v
	vvp $(BUILD_DIR)/fp_int_mac_dsn 
# && gtkwave $(BUILD_DIR)/fp_int_mac.vcd

# Prevent `make all` from triggering the generic rule
ifeq ($(MAKECMDGOALS),all)
else
# Rule to compile and run simulation for other individual modules
$(MAKECMDGOALS):
	@echo "Processing $@..."
	@mkdir -p $(BUILD_DIR)
	iverilog -o $(BUILD_DIR)/$@_dsn $(TB_DIR)/$@_tb.v $(SRC_DIR)/$@.v
	vvp $(BUILD_DIR)/$@_dsn 
# && gtkwave $(BUILD_DIR)/$@.vcd
endif

# Clean rule
clean:
	@echo "Cleaning up..."
	rm -rf $(BUILD_DIR)
