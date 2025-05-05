import os
import subprocess
import struct
# import torch
# from qtorch.quant import fixed_point_quantize
from fxpmath import Fxp
import numpy as np

def float_to_hex(f):
    """Convert float to IEEE 754 half-precision hex string."""
    return f"{struct.unpack('<H', struct.pack('<e', f))[0]:04X}"

def float_to_fixed(val, exp_set):
    """Convert float to fixed-point integer: 22-bit logic using 2^exp_set."""
    scale = 2 ** (10 + 15 - exp_set) # FP16 format has 10-bit mantissa
    return int(val * scale)

def generate_mem_files(N, K, P, exp_set, act_path='tb/act.mem', w_path='tb/w.mem'):
    """Write original act/w.mem values and compute expected results."""
    os.makedirs('tb', exist_ok=True)

    # === Use original values ===
    act = np.array([
        [1.0, 2.0],  # row 0
        [3.0, 1.0]   # row 1
    ])  # Shape (N, K)

    w = np.array([
        [[1, 0, 1, 0], [1, 0, 0, 1]],  # PE row 0
        [[1, 1, 0, 0], [1, 0, 0, 1]]   # PE row 1
    ])  # Shape (N, K, P)

    # Write act.mem (column-major order: K outer, N inner)
    with open(act_path, 'w') as f:
        for row in range(N):
            for col in range(K):
                f.write(f"{float_to_hex(act[row][col])}\n")

    # Write w.mem in bit-serial order: k, p, r
    with open(w_path, 'w') as f:
        for k in range(K):
            for r in range(N):
                for p in range(P):
                    f.write(f"{w[r][k][p]}\n")

        
    # Define fixed-point format (Q22.10)
    WL = 32
    FL = 10

    # Set up accumulators with correct format and overflow mode
    acc = [[0.0 for _ in range(N)] for _ in range(N)]

    print(f"\n✅ Computing expected outputs with EXP_SET = {exp_set} (scale = 2^{exp_set}):")

    for i in range(N):  # act row
        for j in range(N):  # weight column (PE column)
            print(f"\n▶ PE[{i}][{j}]:")
            for k in range(K):
                # Combine P bits into signed integer (MSB first)
                bits = w[k][j]
                bit_str = ''.join(str(b) for b in bits)
                unsigned = int(bit_str, 2)

                # Interpret as signed int using 2's complement
                if bits[0] == 1:
                    signed_int = unsigned - (1 << P)
                else:
                    signed_int = unsigned

                a_val = act[i][k]
                mult_val = a_val * signed_int

                # Accumulate
                acc[i][j] += mult_val

                
                # Wrap and simulate Q22.10 fixed-point output
                fixed_val_fxp = Fxp(mult_val, signed=True, n_word=32, n_frac=10, overflow='wrap')
                acc_fxp = Fxp(acc[i][j], signed=True, n_word=32, n_frac=10, overflow='wrap')

                print(f"  [k={k}] bits = {bits} → int = {signed_int:>4}, "
                    f"act[{i}][{k}] = {a_val:.4f}, mult = {mult_val:.4f}, "
                    f"fixed = {fixed_val_fxp()} (bin: {fixed_val_fxp.bin()}, hex: {fixed_val_fxp.hex()}), "
                    f"acc = {acc_fxp()} (bin: {acc_fxp.bin()}, hex: {acc_fxp.hex()})")
    return acc  # <-- add this line at the end


def run_testbench(N, K, P, EXP_SET):
    """Run make mm with environment overrides."""
    env = os.environ.copy()
    env["N"] = str(N)
    env["K"] = str(K)
    env["P"] = str(P)
    env["EXP_SET"] = str(EXP_SET)

    try:
        subprocess.run(['make', 'mm'], env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Simulation failed: {e}")
    else:
        print("[INFO] Simulation complete.")

def read_verilog_output(filepath):
    outputs = {}
    with open(filepath, 'r') as f:
        for line in f:
            if "PE[" in line and ":" in line:
                parts = line.strip().split(":")
                loc = parts[0].strip()[3:]  # e.g., '0][0]'
                hex_val = parts[1].strip()
                row, col = map(int, loc.replace("]", "").split("["))
                outputs[(row, col)] = int(hex_val, 16)
    return outputs

if __name__ == "__main__":
    N = 2
    K = 2
    P = 4
    EXP_SET = 15

    acc = generate_mem_files(N, K, P, EXP_SET)
    run_testbench(N, K, P, EXP_SET)

    # Read Verilog results
    verilog_results = read_verilog_output("build/verilog_output.txt")

    # Compare with Python fixed-point results
    print("\n🧮 Comparing with Python fixed-point simulation:")
    mismatches = 0
    for i in range(N):
        for j in range(N):
            py_val = Fxp(acc[i][j], signed=True, n_word=32, n_frac=10, overflow='wrap')
            py_int = int(py_val.raw()) & 0xFFFFFFFF  # <<< use .raw() to get Verilog-equivalent int
            verilog_int = verilog_results[(i, j)]
            if py_int != verilog_int:
                print(f"❌ PE[{i}][{j}] MISMATCH: Python = {py_int:08X}, Verilog = {verilog_int:08X}")
                mismatches += 1
            else:
                print(f"✅ PE[{i}][{j}] MATCH: {py_int:08X}")
