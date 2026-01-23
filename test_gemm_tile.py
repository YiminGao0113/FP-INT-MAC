import os
import subprocess
import numpy as np

# ============================================================
# Config
# ============================================================
ACC_WIDTH_DEFAULT = 16   # must match RTL
SEED = 1234              # set None for random

def mask_width(val: int, width: int) -> int:
    return val & ((1 << width) - 1)

# ============================================================
# Memory generation + golden
# Layout (same convention as before):
#   act_mem_full[row*MAX_K + k] = A[row][k]
#   w_mem_full  [col*MAX_K + k] = B[col][k]
# Golden:
#   C[row,col] = sum_k A[row,k] * B[col,k]
# ============================================================
def generate_mem_files_gemm(
    N_FULL: int,
    MAX_K: int,
    K_TOTAL: int,
    act_path="tb/act.mem",
    w_path="tb/w.mem",
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED,
):
    os.makedirs("tb", exist_ok=True)
    rng = np.random.default_rng(seed) if seed is not None else np.random.default_rng()

    # unsigned int4
    A = rng.integers(0, 16, size=(N_FULL, K_TOTAL), dtype=np.uint8)
    B = rng.integers(0, 16, size=(N_FULL, K_TOTAL), dtype=np.uint8)  # B[col,k]

    # pad to MAX_K
    act_mem = np.zeros((N_FULL, MAX_K), dtype=np.uint8)
    w_mem   = np.zeros((N_FULL, MAX_K), dtype=np.uint8)
    act_mem[:, :K_TOTAL] = A
    w_mem[:, :K_TOTAL]   = B

    # write act.mem (row-major by row, then k)
    with open(act_path, "w") as f:
        for r in range(N_FULL):
            for k in range(MAX_K):
                f.write(f"{int(act_mem[r, k]) & 0xF:01X}\n")

    # write w.mem (col-major by col, then k)
    with open(w_path, "w") as f:
        for c in range(N_FULL):
            for k in range(MAX_K):
                f.write(f"{int(w_mem[c, k]) & 0xF:01X}\n")

    # golden C
    C = np.zeros((N_FULL, N_FULL), dtype=np.uint64)
    for r in range(N_FULL):
        for c in range(N_FULL):
            s = 0
            for k in range(K_TOTAL):
                s += int(A[r, k]) * int(B[c, k])
            C[r, c] = mask_width(s, acc_width)

    print("\n✅ Golden C (masked):")
    for r in range(N_FULL):
        print("row %d: %s" % (r, " ".join(f"{int(C[r,c]):>5d}" for c in range(N_FULL))))

    return C

# ============================================================
# Run RTL (Makefile target: gemm4)
# ============================================================
def run_testbench_gemm(N_FULL: int, TILE_N: int, MAX_K: int, K_TILE: int, K_TOTAL: int):
    env = os.environ.copy()
    env["N_FULL"]  = str(N_FULL)
    env["TILE_N"]  = str(TILE_N)
    env["MAX_K"]   = str(MAX_K)
    env["K_TILE"]  = str(K_TILE)
    env["K_TOTAL"] = str(K_TOTAL)

    subprocess.run(["make", "gemm4"], env=env, check=True)
    print("[INFO] Simulation complete.")

# ============================================================
# Parse build/verilog_output.txt
# ============================================================
def read_verilog_output(filepath="build/verilog_output.txt", acc_width=ACC_WIDTH_DEFAULT):
    outputs = {}
    mask = (1 << acc_width) - 1

    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("PE[") and ":" in line:
                left, right = line.split(":", 1)
                loc = left[3:]  # "0][1]"
                r, c = map(int, loc.replace("]", "").split("["))
                val = int(right.strip(), 16) & mask
                outputs[(r, c)] = val

    return outputs

def compare_results(C_py: np.ndarray, C_rtl: dict, acc_width=ACC_WIDTH_DEFAULT):
    mismatches = 0
    mask = (1 << acc_width) - 1
    N_FULL = C_py.shape[0]

    print("\n🧮 Compare RTL vs Python:")
    for r in range(N_FULL):
        for c in range(N_FULL):
            py_val = int(C_py[r, c]) & mask
            rtl_val = C_rtl.get((r, c), None)
            if rtl_val is None:
                print(f"❌ PE[{r}][{c}] missing in RTL output")
                mismatches += 1
            elif py_val != rtl_val:
                print(f"❌ PE[{r}][{c}] MISMATCH: py={py_val} (0x{py_val:04X}) rtl={rtl_val} (0x{rtl_val:04X})")
                mismatches += 1
            else:
                print(f"✅ PE[{r}][{c}] MATCH: {py_val} (0x{py_val:04X})")

    if mismatches:
        print(f"\n⚠️ {mismatches} mismatches found.")
    else:
        print("\n✅ All outputs match.")

def single_test_gemm(
    N_FULL: int,
    TILE_N: int,
    MAX_K: int,
    K_TOTAL: int,
    K_TILE: int,
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED,
):
    # helpful sanity checks
    assert N_FULL % TILE_N == 0, "Need N_FULL divisible by TILE_N"
    assert K_TOTAL <= MAX_K, "Need K_TOTAL <= MAX_K"
    assert (K_TOTAL % K_TILE) == 0, "Your simplified compute_tile assumes K_TOTAL % K_TILE == 0"

    C_py = generate_mem_files_gemm(
        N_FULL=N_FULL, MAX_K=MAX_K, K_TOTAL=K_TOTAL,
        acc_width=acc_width, seed=seed
    )

    run_testbench_gemm(N_FULL=N_FULL, TILE_N=TILE_N, MAX_K=MAX_K, K_TILE=K_TILE, K_TOTAL=K_TOTAL)

    C_rtl = read_verilog_output("build/verilog_output.txt", acc_width=acc_width)
    compare_results(C_py, C_rtl, acc_width=acc_width)

if __name__ == "__main__":
    # Example: 16x16x16 GEMM using 4x4 tile, K_TILE=4 inside compute_tile
    N_FULL  = 16
    MAX_K   = 16
    K_TOTAL = 16
    TILE_N  = 4
    K_TILE  = 4

    single_test_gemm(N_FULL, TILE_N, MAX_K, K_TOTAL, K_TILE, acc_width=ACC_WIDTH_DEFAULT, seed=SEED)