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


# Rule to compile fp_int_mac with dependencies when running `make all`
systolic4:
	@echo "Processing fp_int_mac..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/systolic4_test_dsn $(TB_DIR)/tb_systolic_array4.v $(SRC_DIR)/systolic4.v $(SRC_DIR)/mac4.v 
	vvp $(BUILD_DIR)/systolic4_test_dsn 
# && gtkwave $(BUILD_DIR)/fp_int_mac.vcd

# --- New MM wrapper that feeds systolic4 using act_fifo for BOTH activations & weights ---
mm4:
	@echo "Building & running mm4 testbench..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/mm4_tb.out \
		-s mm_tb \
		-Pmm_tb.N=$(N) \
		-Pmm_tb.K=$(K) \
		$(TB_DIR)/mm4_tb.v \
		$(SRC_DIR)/mm4.v \
		$(SRC_DIR)/systolic4.v \
		$(SRC_DIR)/mac4.v \
		$(SRC_DIR)/act_fifo4.v
	vvp $(BUILD_DIR)/mm4_tb.out

# ---- compute_tile (top wrapper) testbench ----
# Env overrides:
#   N, MAX_K, K_TILE, K_TOTAL
MAX_K   ?= 8
K_TILE  ?= 2
K_TOTAL ?= $(MAX_K)

tile4:
	@echo "Building & running compute_tile testbench..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/tile4_tb.out \
		-s compute_tile_tb \
		-Pcompute_tile_tb.N=$(N) \
		-Pcompute_tile_tb.MAX_K=$(MAX_K) \
		-Pcompute_tile_tb.K_TILE=$(K_TILE) \
		-Pcompute_tile_tb.K_TOTAL=$(K_TOTAL) \
		$(TB_DIR)/compute_tile_tb.v \
		$(SRC_DIR)/compute_tile.v \
		$(SRC_DIR)/mm4.v \
		$(SRC_DIR)/systolic4.v \
		$(SRC_DIR)/mac4.v \
		$(SRC_DIR)/act_fifo4.v
	vvp $(BUILD_DIR)/tile4_tb.out

# ---- gemm_tile (maps N_FULLxN_FULLxK onto TILE_N compute_tile passes) ----
# Env overrides:
#   N_FULL, TILE_N, MAX_K, K_TILE, K_TOTAL
N_FULL ?= 8
TILE_N ?= 4

gemm4:
	@echo "Building & running gemm_tile testbench..."
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/gemm4_tb.out \
		-s gemm_tile_tb \
		-Pgemm_tile_tb.N_FULL=$(N_FULL) \
		-Pgemm_tile_tb.TILE_N=$(TILE_N) \
		-Pgemm_tile_tb.MAX_K=$(MAX_K) \
		-Pgemm_tile_tb.K_TILE=$(K_TILE) \
		-Pgemm_tile_tb.K_TOTAL=$(K_TOTAL) \
		$(TB_DIR)/gemm_tile_tb.v \
		$(SRC_DIR)/gemm_tile.v \
		$(SRC_DIR)/compute_tile.v \
		$(SRC_DIR)/mm4.v \
		$(SRC_DIR)/systolic4.v \
		$(SRC_DIR)/mac4.v \
		$(SRC_DIR)/act_fifo4.v
	vvp $(BUILD_DIR)/gemm4_tb.out

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
int_mac:
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
