import os
import subprocess
import struct
from fxpmath import Fxp
import numpy as np


# =========================================================
# Helpers: FP16 encode/decode
# =========================================================
def float_to_hex(f):
    """Convert float -> IEEE754 half hex string (little-endian)."""
    return f"{struct.unpack('<H', struct.pack('<e', np.float16(f)))[0]:04X}"


def fp16_hex_to_float(hex_str: str) -> float:
    """Convert '0xDF35' / 'DF35' -> Python float (IEEE754 half)."""
    s = hex_str.strip()
    if s.lower().startswith("0x"):
        s = s[2:]
    bits = int(s, 16) & 0xFFFF
    return float(struct.unpack('<e', struct.pack('<H', bits))[0])


# =========================================================
# Memory generation + expected compute
# =========================================================
def generate_mem_files(
    N, K, P, exp_set,
    act_min=0, act_max=8,
    act_path="tb/act.mem",
    w_path="tb/w.mem",
    seed=None
):
    """Write tb/act.mem + tb/w.mem, and compute expected float acc (Python-side)."""
    os.makedirs("tb", exist_ok=True)

    if seed is not None:
        np.random.seed(seed)

    # Activations: float16
    act = np.random.uniform(act_min, act_max, size=(N, K)).astype(np.float16)

    # Weights: bits shape (N, K, P)
    w = np.random.randint(0, 2, size=(N, K, P), dtype=np.int8)

    # act.mem: row-major (matches your current file writer)
    with open(act_path, "w") as f:
        for row in range(N):
            for col in range(K):
                f.write(f"{float_to_hex(act[row][col])}\n")

    # w.mem: r, k, p (matches your current writer)
    with open(w_path, "w") as f:
        for r in range(N):
            for k in range(K):
                for p in range(P):
                    f.write(f"{int(w[r][k][p])}\n")

    # Expected output float accumulator (not yet quantized to fp16)
    acc = [[0.0 for _ in range(N)] for _ in range(N)]

    print(f"\n✅ Computing expected outputs with EXP_SET = {exp_set} (note: EXP_SET not used in pure-float expectation):")

    for i in range(N):      # activation row
        for j in range(N):  # weight column / PE column
            print(f"\n▶ PE[{i}][{j}]:")
            for k in range(K):
                bits = w[j][k]  # NOTE: keeping your original convention
                bit_str = ''.join(str(int(b)) for b in bits)
                unsigned = int(bit_str, 2)

                # signed 2's complement on P bits
                if bits[0] == 1:
                    signed_int = unsigned - (1 << P)
                else:
                    signed_int = unsigned

                a_val = float(np.float32(act[i][k]))
                mult_val = a_val * signed_int
                acc[i][j] += mult_val

                fixed_val_fxp = Fxp(mult_val, signed=True, n_word=32, n_frac=10, overflow='wrap')
                acc_fxp = Fxp(acc[i][j], signed=True, n_word=32, n_frac=10, overflow='wrap')

                print(
                    f"  [k={k}] bits={bits.tolist()} → int={signed_int:>4}, "
                    f"act[{i}][{k}]={a_val:.4f} (hex:{float_to_hex(act[i][k])}), mult={mult_val:.4f}, "
                    f"fixed={fixed_val_fxp()} (hex:{fixed_val_fxp.hex()}), "
                    f"acc={acc_fxp()} (hex:{acc_fxp.hex()})"
                )

    return acc


# =========================================================
# Run Verilog sim
# =========================================================
def run_testbench(N, K, P, EXP_SET):
    """Run `make mm` with environment overrides."""
    env = os.environ.copy()
    env["N"] = str(N)
    env["K"] = str(K)
    env["P"] = str(P)
    env["EXP_SET"] = str(EXP_SET)

    try:
        subprocess.run(["make", "mm"], env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Simulation failed: {e}")
        raise
    else:
        print("[INFO] Simulation complete.")


# =========================================================
# Read Verilog output (FP16 hex)
# Expected line format in build/verilog_output.txt:
#   PE[i][j]: 0xDF35
# or
#   PE[i][j]: DF35
# =========================================================
def read_verilog_output_fp16(filepath):
    outputs = {}
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("PE[") and ":" in line:
                left, right = line.split(":", 1)
                loc = left[3:]  # "0][0]"
                row, col = map(int, loc.replace("]", "").split("["))
                hex_val = right.strip()
                outputs[(row, col)] = fp16_hex_to_float(hex_val)
    return outputs


# =========================================================
# Single test: compare Python float vs Verilog fp16 float
# =========================================================
def single_test(N, K, P, ACT_MIN, ACT_MAX, EXP_SET, tolerance=1e-2, seed=None, compare_fp16=True):
    """
    compare_fp16=True:
        compares (np.float16(python_acc)) vs (verilog_fp16)
        (most fair, because Verilog output is fp16)
    compare_fp16=False:
        compares python float accumulator vs verilog fp16 (will show quantization diffs)
    """
    acc = generate_mem_files(N, K, P, EXP_SET, act_min=ACT_MIN, act_max=ACT_MAX, seed=seed)
    run_testbench(N, K, P, EXP_SET)

    verilog_results = read_verilog_output_fp16("build/verilog_output.txt")

    print("\n🧮 Comparing Verilog FP16 output with Python simulation:")
    mismatches = 0

    for i in range(N):
        for j in range(N):
            if (i, j) not in verilog_results:
                print(f"❌ Missing Verilog output for PE[{i}][{j}]")
                mismatches += 1
                continue

            py_float = float(acc[i][j])
            if compare_fp16:
                py_ref = float(np.float16(py_float))  # quantize reference to fp16
            else:
                py_ref = py_float

            verilog_float = float(verilog_results[(i, j)])
            diff = abs(py_ref - verilog_float)

            if diff > tolerance:
                print(
                    f"❌ PE[{i}][{j}] MISMATCH: Python_ref = {py_ref:.6f}, "
                    f"Verilog(fp16) = {verilog_float:.6f}, Δ = {diff:.6f}"
                )
                mismatches += 1
            else:
                print(f"✅ PE[{i}][{j}] MATCH: Python_ref = {py_ref:.6f} ≈ Verilog(fp16) = {verilog_float:.6f}")

    print(f"\n⚠️ {mismatches} mismatches found." if mismatches else "\n✅ All outputs match.")


# =========================================================
# Multi test
# =========================================================
def multi_test(N, K, P, ACT_MIN, ACT_MAX, EXP_SET, num_trials=10, tolerance=1e-2, compare_fp16=True):
    total_bad = 0
    for trial in range(num_trials):
        print(f"\n🔁 Trial {trial + 1}/{num_trials}")
        seed = None  # or set seed=trial for deterministic
        try:
            single_test(
                N, K, P,
                ACT_MIN, ACT_MAX,
                EXP_SET,
                tolerance=tolerance,
                seed=seed,
                compare_fp16=compare_fp16
            )
        except Exception:
            total_bad += 1
            print(f"⚠️ Trial {trial + 1}: simulation failed.\n")
    print(f"\n🎯 Done. {num_trials} tests run. Failed trials: {total_bad}")


# =========================================================
# Entry
# =========================================================
if __name__ == "__main__":
    N = 8
    K = 8
    P = 4
    EXP_SET = 15
    ACT_MAX = 128
    ACT_MIN = 2

    NUM_TRIALS = 10
    TOLERANCE = 1e-1  # FP16 is quantized; 0 is usually too strict

    # Single test
    single_test(N, K, P, ACT_MIN, ACT_MAX, EXP_SET, tolerance=TOLERANCE, seed=None, compare_fp16=True)

    # Or multi test
    # multi_test(N, K, P, ACT_MIN, ACT_MAX, EXP_SET, num_trials=NUM_TRIALS, tolerance=TOLERANCE, compare_fp16=True)