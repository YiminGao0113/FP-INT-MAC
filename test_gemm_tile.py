import os
import subprocess
import numpy as np

# ============================================================
# Config
# ============================================================
ACC_WIDTH_DEFAULT = 16   # must match RTL
SEED = 1234              # set None for random

# Signed int4 range: [-8, 7]
INT4_MIN = -8
INT4_MAX = 7

def to_twos_complement_hex(val: int, bits: int) -> str:
    """Return hex string for val encoded as two's complement with given bit width."""
    mask = (1 << bits) - 1
    return f"{(val & mask):X}"

def wrap_signed(val: int, bits: int) -> int:
    """Wrap integer into signed two's-complement range of 'bits'."""
    mask = (1 << bits) - 1
    v = val & mask
    sign = 1 << (bits - 1)
    return v - (1 << bits) if (v & sign) else v

# ============================================================
# Memory generation + golden (SIGNED int4 × SIGNED int4)
# Layout (same convention as before):
#   act_mem_full[row*MAX_K + k] = A[row][k]
#   w_mem_full  [col*MAX_K + k] = B[col][k]
# Golden:
#   C[row,col] = sum_k A[row,k] * B[col,k]  (wrapped to signed ACC_WIDTH)
# ============================================================
def generate_mem_files_gemm_signed(
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

    # signed int4
    A = rng.integers(INT4_MIN, INT4_MAX + 1, size=(N_FULL, K_TOTAL), dtype=np.int16)
    B = rng.integers(INT4_MIN, INT4_MAX + 1, size=(N_FULL, K_TOTAL), dtype=np.int16)  # B[col,k]

    # pad to MAX_K
    act_mem = np.zeros((N_FULL, MAX_K), dtype=np.int16)
    w_mem   = np.zeros((N_FULL, MAX_K), dtype=np.int16)
    act_mem[:, :K_TOTAL] = A
    w_mem[:, :K_TOTAL]   = B

    # write act.mem (row-major by row, then k), each entry as 4-bit two's complement hex nibble
    with open(act_path, "w") as f:
        for r in range(N_FULL):
            for k in range(MAX_K):
                f.write(to_twos_complement_hex(int(act_mem[r, k]), 4) + "\n")

    # write w.mem (col-major by col, then k)
    with open(w_path, "w") as f:
        for c in range(N_FULL):
            for k in range(MAX_K):
                f.write(to_twos_complement_hex(int(w_mem[c, k]), 4) + "\n")

    # golden C (signed wrap to acc_width)
    C = np.zeros((N_FULL, N_FULL), dtype=np.int64)
    for r in range(N_FULL):
        for c in range(N_FULL):
            s = 0
            for k in range(K_TOTAL):
                s += int(A[r, k]) * int(B[c, k])
            C[r, c] = wrap_signed(s, acc_width)

    print("\n✅ Golden C (signed, wrapped to ACC_WIDTH):")
    for r in range(N_FULL):
        print("row %d: %s" % (r, " ".join(f"{int(C[r,c]):>6d}" for c in range(N_FULL))))

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
# TB prints hex. For signed compare, decode as signed ACC_WIDTH.
# ============================================================
def read_verilog_output_signed(filepath="build/verilog_output.txt", acc_width=ACC_WIDTH_DEFAULT):
    outputs = {}
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("PE[") and ":" in line:
                left, right = line.split(":", 1)
                loc = left[3:]  # "0][1]"
                r, c = map(int, loc.replace("]", "").split("["))
                raw = int(right.strip(), 16)
                outputs[(r, c)] = wrap_signed(raw, acc_width)
    return outputs

def compare_results_signed(C_py: np.ndarray, C_rtl: dict, acc_width=ACC_WIDTH_DEFAULT):
    mismatches = 0
    N_FULL = C_py.shape[0]

    print("\n🧮 Compare RTL vs Python (SIGNED):")
    for r in range(N_FULL):
        for c in range(N_FULL):
            py_val  = wrap_signed(int(C_py[r, c]), acc_width)
            rtl_val = C_rtl.get((r, c), None)
            if rtl_val is None:
                print(f"❌ PE[{r}][{c}] missing in RTL output")
                mismatches += 1
            elif py_val != rtl_val:
                # show both signed and hex form
                py_hex  = int(py_val) & ((1 << acc_width) - 1)
                rtl_hex = int(rtl_val) & ((1 << acc_width) - 1)
                print(f"❌ PE[{r}][{c}] MISMATCH: py={py_val} (0x{py_hex:04X}) rtl={rtl_val} (0x{rtl_hex:04X})")
                mismatches += 1
            else:
                py_hex = int(py_val) & ((1 << acc_width) - 1)
                print(f"✅ PE[{r}][{c}] MATCH: {py_val} (0x{py_hex:04X})")

    if mismatches:
        print(f"\n⚠️ {mismatches} mismatches found.")
    else:
        print("\n✅ All outputs match.")

def single_test_gemm_signed(
    N_FULL: int,
    TILE_N: int,
    MAX_K: int,
    K_TOTAL: int,
    K_TILE: int,
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED,
):
    # sanity checks
    assert N_FULL % TILE_N == 0, "Need N_FULL divisible by TILE_N"
    assert K_TOTAL <= MAX_K, "Need K_TOTAL <= MAX_K"
    assert (K_TOTAL % K_TILE) == 0, "Your simplified compute_tile assumes K_TOTAL % K_TILE == 0"

    C_py = generate_mem_files_gemm_signed(
        N_FULL=N_FULL, MAX_K=MAX_K, K_TOTAL=K_TOTAL,
        acc_width=acc_width, seed=seed
    )

    run_testbench_gemm(N_FULL=N_FULL, TILE_N=TILE_N, MAX_K=MAX_K, K_TILE=K_TILE, K_TOTAL=K_TOTAL)

    C_rtl = read_verilog_output_signed("build/verilog_output.txt", acc_width=acc_width)
    compare_results_signed(C_py, C_rtl, acc_width=acc_width)

if __name__ == "__main__":
    # Example: 16x16x16 GEMM using 4x4 tile, K_TILE=4 inside compute_tile
    N_FULL  = 16
    MAX_K   = 16
    K_TOTAL = 16
    TILE_N  = 4
    K_TILE  = 4

    single_test_gemm_signed(N_FULL, TILE_N, MAX_K, K_TOTAL, K_TILE, acc_width=ACC_WIDTH_DEFAULT, seed=SEED)