# Flexible Makefile for compiling Verilog code with Icarus Verilog and viewing with GTKWave

# Directory for output files
BUILD_DIR := build
SRC_DIR := src
TB_DIR := tb

# Default parameter values (override via environment if needed)
N ?= 2
K ?= 2
P ?= 4
EXP_SET ?= 15


# Phony targets
.PHONY: all clean fp_int_mac $(MAKECMDGOALS)

# Default target
all: fp_int_mac

# Rule to compile fp_int_mac with dependencies when running `make all`
systolic:
	@echo "Processing fp_int_mac..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/systolic_test_dsn $(TB_DIR)/systolic_tb.v $(SRC_DIR)/systolic.v $(SRC_DIR)/fifo.v $(SRC_DIR)/fp_int_mac.v $(SRC_DIR)/fp_int_mul.v $(SRC_DIR)/fp_int_acc.v
	vvp $(BUILD_DIR)/systolic_test_dsn 
# && gtkwave $(BUILD_DIR)/fp_int_mac.vcd

mm:
	@echo "Running mm_tb with systolic..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 \
		-P mm_tb.N=$(N) \
		-P mm_tb.K=$(K) \
		-P mm_tb.P=$(P) \
		-P mm_tb.EXP=$(EXP_SET) \
	    -o $(BUILD_DIR)/mm_tb_dsn \
		$(TB_DIR)/mm_tb.v \
		$(SRC_DIR)/mm.v \
		$(SRC_DIR)/systolic.v \
		$(SRC_DIR)/act_fifo.v \
		$(SRC_DIR)/fifo.v \
		$(SRC_DIR)/fp_int_mac.v \
		$(SRC_DIR)/fp_int_mul.v \
		$(SRC_DIR)/fp_int_acc.v
	vvp $(BUILD_DIR)/mm_tb_dsn



# Rule to compile fp_int_mac with dependencies when running `make all`
fp_int_mac:
	@echo "Processing systolic..."
	@mkdir -p $(BUILD_DIR)
	iverilog -o $(BUILD_DIR)/fp_int_mac_dsn $(TB_DIR)/fp_int_mac_tb.v $(SRC_DIR)/fp_int_mac.v $(SRC_DIR)/fp_int_mul.v $(SRC_DIR)/fp_int_acc.v
	vvp $(BUILD_DIR)/fp_int_mac_dsn 
# && gtkwave $(BUILD_DIR)/fp_int_mac.vcd

# Prevent `make all` from triggering the generic rule
# ifeq ($(MAKECMDGOALS),all)
# else
# # Rule to compile and run simulation for other individual modules
# $(MAKECMDGOALS):
# 	@echo "Processing $@..."
# 	@mkdir -p $(BUILD_DIR)
# 	iverilog -o $(BUILD_DIR)/$@_dsn $(TB_DIR)/$@_tb.v $(SRC_DIR)/$@.v
# 	vvp $(BUILD_DIR)/$@_dsn 
# # && gtkwave $(BUILD_DIR)/$@.vcd
# endif

# Clean rule
clean:
	@echo "Cleaning up..."
	rm -rf $(BUILD_DIR)
	rm $(TB_DIR)/*.mem
