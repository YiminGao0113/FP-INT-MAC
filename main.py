import os
import subprocess
import numpy as np
import struct

def float_to_hex(f):
    """Convert float to IEEE 754 half-precision hex string."""
    return f"{struct.unpack('<H', struct.pack('<e', f))[0]:04X}"

def float_to_fp22(val, exp_set):
    """Convert float to fixed-point integer: 22-bit logic using 2^exp_set."""
    scale = 2 ** exp_set
    return int(val * scale)

def generate_mem_files(N, K, P, exp_set, act_path='tb/act.mem', w_path='tb/w.mem'):
    """Write original act/w.mem values and compute expected results."""
    os.makedirs('tb', exist_ok=True)

    # === Use original values ===
    act = np.array([
        [1.0, 3.0],  # row 0
        [2.0, 1.0]   # row 1
    ])  # Shape (N, K)

    w = np.array([
        [[1, 0, 1, 0], [1, 0, 0, 1]],  # PE row 0
        [[1, 1, 0, 0], [1, 0, 0, 1]]   # PE row 1
    ])  # Shape (N, K, P)

    # Write act.mem (column-major order: K outer, N inner)
    with open(act_path, 'w') as f:
        for col in range(K):
            for row in range(N):
                f.write(f"{float_to_hex(act[row][col])}\n")

    # Write w.mem in bit-serial order: k, p, r
    with open(w_path, 'w') as f:
        for k in range(K):
            for r in range(N):
                for p in range(P):
                    f.write(f"{w[r][k][p]}\n")

    # === Compute expected output ===
    acc = np.zeros((N, N), dtype=np.int32)
    for i in range(N):  # act row
        for j in range(N):  # w row / PE column
            for k in range(K):
                for p in range(P):
                    a_val = act[i][k]
                    w_bit = w[j][k][p]
                    mult = a_val * w_bit
                    acc[i][j] += float_to_fp22(mult, exp_set)

    print(f"\n✅ Computed expected outputs:")
    for i in range(N):
        for j in range(N):
            val = int(acc[i][j])
            val_signed = (val + (1 << 32)) % (1 << 32)
            if val_signed & (1 << 31):
                val_signed -= (1 << 32)
            print(f"PE[{i}][{j}] = {val_signed:#010x} ({val_signed})")

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

if __name__ == "__main__":
    N = 2
    K = 2
    P = 4
    EXP_SET = 15

    generate_mem_files(N, K, P, EXP_SET)
    run_testbench(N, K, P, EXP_SET)
