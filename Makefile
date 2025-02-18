# Flexible Makefile for compiling Verilog code with Icarus Verilog and viewing with GTKWave

# Directory for output files
BUILD_DIR := build
SRC_DIR := src
TB_DIR := tb

# Phony target to handle any base name, clean, and all
.PHONY: all clean $(MAKECMDGOALS)

# Default target
all:
	@echo "Usage: make <base_file_name_without_extension>"
	@echo "Example: make test (for test.v and test_tb.v)"

# Rule to compile, run simulation, open GTKWave, and clean after closing GTKWave
$(MAKECMDGOALS):
	@echo "Processing $@..."
	@mkdir -p $(BUILD_DIR)
	iverilog -o $(BUILD_DIR)/$@_dsn $(TB_DIR)/$@_tb.v $(SRC_DIR)/$@.v && vvp $(BUILD_DIR)/$@_dsn 
# && gtkwave $(BUILD_DIR)/$@.vcd

# Clean rule
clean:
	@echo "Cleaning up..."
	rm -rf $(BUILD_DIR)