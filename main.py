import os
import subprocess
import numpy as np

def generate_mem_files(N, K, P, act_path='tb/act.mem', w_path='tb/w.mem'):
    """Generate int4 activation and weight memory files, and compute expected results."""
    os.makedirs('tb', exist_ok=True)

    # Generate signed INT4 activations and weights: values in [-8, 7]
    act = np.random.randint(-8, 8, size=(N, K), dtype=np.int8)
    w_vals = np.random.randint(-8, 8, size=(N, K), dtype=np.int8)

    # Write act.mem in column-major order (K outer, N inner)
    with open(act_path, 'w') as f:
        for row in range(N):
            for col in range(K):
                f.write(f"{act[row][col] & 0xF:01X}\n")  # store as 4-bit hex

    # Write w.mem in bit-serial order from LSB to MSB
    with open(w_path, 'w') as f:
        for r in range(N):
            for k in range(K):
                val = w_vals[r][k] & 0xF  # get the 4-bit 2's complement representation
                for p in range(P):  # LSB to MSB
                    bit = (val >> p) & 0x1
                    f.write(f"{bit}\n")

    # Compute expected output: act[i][k] * w_vals[j][k]
    acc = [[0 for _ in range(N)] for _ in range(N)]
    for i in range(N):      # act row
        for j in range(N):  # weight column
            for k in range(K):
                a = int(act[i][k])
                b = int(w_vals[j][k]) if w_vals[j][k] < 8 else w_vals[j][k] - 16
                acc[i][j] += a * b

    print("\n✅ Computed expected INT4 × INT4 outputs:")
    for i in range(N):
        for j in range(N):
            print(f"PE[{i}][{j}] = {acc[i][j]}")
    return acc

def run_testbench(N, K, P):
    """Call make mm with environment overrides."""
    env = os.environ.copy()
    env["N"] = str(N)
    env["K"] = str(K)
    env["P"] = str(P)

    try:
        subprocess.run(['make', 'mm'], env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Simulation failed: {e}")
    else:
        print("[INFO] Simulation complete.")

def read_verilog_output(filepath):
    """Parse Verilog output file and return dictionary of signed 16-bit results."""
    outputs = {}
    with open(filepath, 'r') as f:
        for line in f:
            if "PE[" in line and ":" in line:
                parts = line.strip().split(":")
                loc = parts[0].strip()[3:]  # e.g., '0][0]'
                hex_val = parts[1].strip()
                row, col = map(int, loc.replace("]", "").split("["))
                val = int(hex_val, 16)
                if val >= (1 << 15):  # Signed 16-bit conversion
                    val -= (1 << 16)
                outputs[(row, col)] = val
    return outputs


def single_test(N, K, P):
    """Run one int4 × int4 test and compare Python vs Verilog."""
    acc = generate_mem_files(N, K, P)
    run_testbench(N, K, P)
    verilog_results = read_verilog_output("build/verilog_output.txt")

    print("\n🧮 Comparing Verilog output with Python result:")
    mismatches = 0
    for i in range(N):
        for j in range(N):
            py_val = acc[i][j]
            verilog_val = verilog_results.get((i, j), None)

            if verilog_val is None:
                print(f"❌ PE[{i}][{j}] missing from Verilog output.")
                mismatches += 1
                continue

            if py_val != verilog_val:
                print(f"❌ PE[{i}][{j}] MISMATCH: Python = {py_val}, Verilog = {verilog_val}")
                mismatches += 1
            else:
                print(f"✅ PE[{i}][{j}] MATCH: {py_val}")

    print(f"\n⚠️ {mismatches} mismatches found." if mismatches else "\n✅ All outputs match.")

if __name__ == "__main__":
    N = 8      # number of rows/columns (PEs)
    K = 8      # input channels
    P = 4      # bit-serial width for int4 weights

    single_test(N, K, P)
