# An Energy-Efficient and Precision-Scalable Accelerator for FP-INT GEMM in Edge LLM Inference

## Project Overview

This project implements an **FP16-INT MAC (Multiply-Accumulate) Unit** that computes MAC operations using **shift-and-add** in a **bit-serial fashion**. The unit is designed to efficiently perform mixed-precision arithmetic for machine learning and other hardware-accelerated applications.

### Key Features:
- Supports **FP16** and **variable-precision INT** arithmetic.
- Computes **MAC operations** using a shift-and-add technique.
- **Bit-serial** implementation to reduce area and power consumption in hardware.
- Verilog implementation for simulation and hardware integration.

## Tools Required

- **Icarus Verilog (iverilog)**: Verilog compiler to compile the testbench and module.
- **GTKWave**: A waveform viewer to visualize the simulation output.

You can install these tools as follows:

### Installing Icarus Verilog (iverilog) and GTKWave
- On Ubuntu:
  ```bash
  sudo apt-get install iverilog gtkwave
  ```
- On macOS:
  ```bash
  brew install iverilog gtkwave
  ```

## How to Run the Simulation

1. Clone this repository:
   ```bash
   git clone https://github.com/YiminGao0113/FP-INT-MAC.git
   cd FP-INT-MAC
   ```
2. Run the simulation: (e.g. to simulate fp_int_mul unit run make fp_int_mul)
   ```bash
   make design_name
   ```
   To simulate for fp_int_mac run 
   ```bash
   make all
   ```
3. Expected Results should show that the results passed simulation verification.
4. If you want to observe the generated waveform, run gtkwave:
   ```bash
   gtkwave build/design_name.vcd
   ```
5. To clean the generated temp files:
   ```bash
   make clean
   ```
## Test the systolic
   ```bash
   iverilog -g2012 -o systolic_test tb/systolic_tb.v   src/systolic.v src/fifo.v src/fp_int_mac.v src/fp_int_mul.v src/fp_int_acc.v
   ```

## Block diagram of the FP16-VariableInt unit
![image](https://github.com/user-attachments/assets/be9a95a6-bc4c-4e2b-828c-b2c4beb3a58b)
## Overall architecture of an energy-efficient, precision-scalable dataflow Accelerator for FP-INT GEMM 
![image](https://github.com/user-attachments/assets/ab977612-e905-4e00-91c1-29c2a66dae62)

## To do
- Finish the Accumulation module for Integer (done✅)
- Implement and verify the entire MAC operation (done✅)
- Implement and verify the bit-serial weight stream FP-INT MAC unit (done✅)
- Implement and verify the MAC unit for Posit4 (done✅)
- Integrate the FP-INT unit as PE into an existing systolic array project
- Integrate synthesis flow into the Repo
