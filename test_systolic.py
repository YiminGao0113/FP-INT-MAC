import os
import subprocess
import numpy as np

# ---- Config (edit if needed) ----
ACC_WIDTH_DEFAULT = 16   # must match your Verilog ACC width
SEED = 1234              # set None for random each run

def _mask_width(val, width):
    return val & ((1 << width) - 1)

def generate_mem_files(
    N, K,
    act_path='tb/act.mem',
    w_path='tb/w.mem',
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED
):
    """
    Generate UNSIGNED INT4 activation and weight memory files and compute expected C.
    A[i,k] in [0..15], W[j,k] in [0..15].
    Files store one 4-bit hex nibble per line (no bit-serial).
    """
    os.makedirs('tb', exist_ok=True)
    if seed is not None:
        rng = np.random.default_rng(seed)
    else:
        rng = np.random.default_rng()

    # Unsigned INT4 (0..15)
    A = rng.integers(0, 16, size=(N, K), dtype=np.uint8)
    W = rng.integers(0, 16, size=(N, K), dtype=np.uint8)  # W[j,k] holds column j's K-tap weights

    # ---- Write act.mem ----
    # Order: i in 0..N-1 (rows), then k in 0..K-1 (columns)
    # If your TB expects time-major (k outer, i inner), swap the loop order.
    with open(act_path, 'w') as f:
        for i in range(N):
            for k in range(K):
                f.write(f"{int(A[i, k]) & 0xF:01X}\n")

    # ---- Write w.mem ----
    # Order: j in 0..N-1 (columns), then k in 0..K-1 (depth)
    # If your TB expects a different order, swap as needed.
    with open(w_path, 'w') as f:
        for j in range(N):
            for k in range(K):
                f.write(f"{int(W[j, k]) & 0xF:01X}\n")

    # ---- Compute expected C = A (N×K) × W^T (N×K) column form ----
    # C[i,j] = sum_k A[i,k] * W[j,k]; all unsigned; wrap to acc_width
    C = np.zeros((N, N), dtype=np.uint64)
    for i in range(N):
        for j in range(N):
            s = 0
            for k in range(K):
                a = int(A[i, k])  # 0..15
                b = int(W[j, k])  # 0..15
                s += a * b
            C[i, j] = _mask_width(s, acc_width)

    # Pretty-print
    print("\n✅ Computed expected UNSIGNED INT4×INT4 outputs (masked to ACC width):")
    for i in range(N):
        row_str = " ".join(f"{C[i,j]:>5d}" for j in range(N))
        print(f"row {i}: {row_str}")

    return C

def run_testbench(N, K, P_unused=4):
    """
    Call `make mm` with environment overrides.
    P is kept for compatibility but unused for non-bit-serial tests.
    """
    env = os.environ.copy()
    env["N"] = str(N)
    env["K"] = str(K)
    # env["P"] = str(P_unused)  # harmless; your Verilog won't use it now
    try:
        subprocess.run(['make', 'mm4'], env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Simulation failed: {e}")
    else:
        print("[INFO] Simulation complete.")

def read_verilog_output(filepath, acc_width=ACC_WIDTH_DEFAULT):
    """
    Parse Verilog output file and return dict of UNSIGNED results.
    Expected lines like: 'PE[0][1]: 00AF' (hex).
    """
    outputs = {}
    mask = (1 << acc_width) - 1
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if "PE[" in line and ":" in line:
                parts = line.split(":")
                loc = parts[0].strip()[3:]  # after "PE"
                hex_val = parts[1].strip()
                i, j = map(int, loc.replace("]", "").split("["))
                val = int(hex_val, 16) & mask  # keep UNSIGNED
                outputs[(i, j)] = val
    return outputs

def compare_results(C_py, C_rtl, acc_width=ACC_WIDTH_DEFAULT):
    mismatches = 0
    mask = (1 << acc_width) - 1
    print("\n🧮 Comparing Verilog output with Python (unsigned, masked):")
    N = C_py.shape[0]
    for i in range(N):
        for j in range(N):
            py_val = int(C_py[i, j]) & mask
            rtl_val = C_rtl.get((i, j), None)
            if rtl_val is None:
                print(f"❌ PE[{i}][{j}] missing from Verilog output.")
                mismatches += 1
                continue
            if py_val != rtl_val:
                print(f"❌ PE[{i}][{j}] MISMATCH: Python = {py_val} (0x{py_val:04X}), "
                      f"Verilog = {rtl_val} (0x{rtl_val:04X})")
                mismatches += 1
            else:
                print(f"✅ PE[{i}][{j}] MATCH: {py_val} (0x{py_val:04X})")
    if mismatches:
        print(f"\n⚠️ {mismatches} mismatches found.")
    else:
        print("\n✅ All outputs match.")

def single_test(N, K, P_unused=4, acc_width=ACC_WIDTH_DEFAULT):
    C_py = generate_mem_files(N, K, acc_width=acc_width)
    run_testbench(N, K, P_unused)
    verilog_results = read_verilog_output("build/verilog_output.txt", acc_width=acc_width)
    compare_results(C_py, verilog_results, acc_width=acc_width)

if __name__ == "__main__":
    N = 8   # array dimension
    K = 8   # inner dimension
    P = 4   # unused now; keep for Makefile compatibility
    single_test(N, K, P, acc_width=ACC_WIDTH_DEFAULT)
