import os
import subprocess
import numpy as np

# ============================================================
# Config
# ============================================================
ACC_WIDTH_DEFAULT = 16   # must match RTL ACC_WIDTH
SEED = 1234              # set None for random each run

# Tile controls (these must match your compute_tile_tb params)
N_DEFAULT      = 8
MAX_K_DEFAULT  = 8       # allocated depth in act_mem/w_mem
K_TOTAL_DEFAULT= 8       # actual depth to run (<= MAX_K)
K_TILE_DEFAULT = 8       # tile chunk size (compute_tile will loop over K_TOTAL in steps of K_TILE)


def mask_width(val: int, width: int) -> int:
    return val & ((1 << width) - 1)


# ============================================================
# Memory generation + golden (unsigned int4 × unsigned int4)
# Layout matches your earlier convention:
#   act_mem index = i*MAX_K + k   (row-major by row, then k)
#   w_mem   index = j*MAX_K + k   (column-major by col, then k)
# so C[i,j] = sum_k A[i,k] * W[j,k]
# ============================================================
def generate_mem_files_tile(
    N: int,
    MAX_K: int,
    K_TOTAL: int,
    act_path="tb/act.mem",
    w_path="tb/w.mem",
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED,
):
    os.makedirs("tb", exist_ok=True)
    rng = np.random.default_rng(seed) if seed is not None else np.random.default_rng()

    # Unsigned INT4
    A = rng.integers(0, 16, size=(N, K_TOTAL), dtype=np.uint8)
    W = rng.integers(0, 16, size=(N, K_TOTAL), dtype=np.uint8)  # W[j,k] = column-j weights

    # Pad to MAX_K if needed
    act_mem = np.zeros((N, MAX_K), dtype=np.uint8)
    w_mem   = np.zeros((N, MAX_K), dtype=np.uint8)
    act_mem[:, :K_TOTAL] = A
    w_mem[:, :K_TOTAL]   = W

    # Write act.mem: i outer, k inner, total N*MAX_K lines
    with open(act_path, "w") as f:
        for i in range(N):
            for k in range(MAX_K):
                f.write(f"{int(act_mem[i, k]) & 0xF:01X}\n")

    # Write w.mem: j outer, k inner, total N*MAX_K lines
    with open(w_path, "w") as f:
        for j in range(N):
            for k in range(MAX_K):
                f.write(f"{int(w_mem[j, k]) & 0xF:01X}\n")

    # Golden C (wrap to acc_width)
    C = np.zeros((N, N), dtype=np.uint64)
    for i in range(N):
        for j in range(N):
            s = 0
            for k in range(K_TOTAL):
                s += int(A[i, k]) * int(W[j, k])
            C[i, j] = mask_width(s, acc_width)

    print("\n✅ Golden (unsigned INT4×INT4), masked to ACC width:")
    for i in range(N):
        print("row %d: %s" % (i, " ".join(f"{int(C[i,j]):>5d}" for j in range(N))))

    return C


# ============================================================
# Run the tile testbench (Makefile target: tile4)
# Expects your Makefile to have:
#   tile4: ... -s compute_tile_tb -Pcompute_tile_tb.N=... etc
# ============================================================
def run_testbench_tile(N: int, MAX_K: int, K_TILE: int, K_TOTAL: int):
    env = os.environ.copy()
    env["N"]       = str(N)
    env["MAX_K"]   = str(MAX_K)
    env["K_TILE"]  = str(K_TILE)
    env["K_TOTAL"] = str(K_TOTAL)

    subprocess.run(["make", "tile4"], env=env, check=True)
    print("[INFO] Simulation complete.")


# ============================================================
# Parse build/verilog_output.txt
# Expected lines like:
#   PE[0][1]: 00AF
# (hex)
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
                i, j = map(int, loc.replace("]", "").split("["))
                hex_val = right.strip()
                val = int(hex_val, 16) & mask
                outputs[(i, j)] = val

    return outputs


def compare_results(C_py: np.ndarray, C_rtl: dict, acc_width=ACC_WIDTH_DEFAULT):
    mismatches = 0
    mask = (1 << acc_width) - 1
    N = C_py.shape[0]

    print("\n🧮 Compare RTL vs Python (unsigned, masked):")
    for i in range(N):
        for j in range(N):
            py_val = int(C_py[i, j]) & mask
            rtl_val = C_rtl.get((i, j), None)
            if rtl_val is None:
                print(f"❌ PE[{i}][{j}] missing in RTL output")
                mismatches += 1
                continue
            if py_val != rtl_val:
                print(f"❌ PE[{i}][{j}] MISMATCH: py={py_val} (0x{py_val:04X}) rtl={rtl_val} (0x{rtl_val:04X})")
                mismatches += 1
            else:
                print(f"✅ PE[{i}][{j}] MATCH: {py_val} (0x{py_val:04X})")

    if mismatches:
        print(f"\n⚠️ {mismatches} mismatches found.")
    else:
        print("\n✅ All outputs match.")


def single_test_tile(
    N=N_DEFAULT,
    MAX_K=MAX_K_DEFAULT,
    K_TOTAL=K_TOTAL_DEFAULT,
    K_TILE=K_TILE_DEFAULT,
    acc_width=ACC_WIDTH_DEFAULT,
    seed=SEED,
):
    # 1) Generate mems + golden
    C_py = generate_mem_files_tile(
        N=N, MAX_K=MAX_K, K_TOTAL=K_TOTAL,
        acc_width=acc_width, seed=seed
    )

    # 2) Run RTL
    run_testbench_tile(N=N, MAX_K=MAX_K, K_TILE=K_TILE, K_TOTAL=K_TOTAL)

    # 3) Read + compare
    C_rtl = read_verilog_output("build/verilog_output.txt", acc_width=acc_width)
    compare_results(C_py, C_rtl, acc_width=acc_width)


if __name__ == "__main__":
    # You can tweak these quickly:
    N       = 8
    MAX_K   = 8
    K_TOTAL = 8
    K_TILE  = 4   # test tiling behavior (must divide or wrapper must handle tail)

    single_test_tile(N=N, MAX_K=MAX_K, K_TOTAL=K_TOTAL, K_TILE=K_TILE, acc_width=ACC_WIDTH_DEFAULT, seed=SEED)