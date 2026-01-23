`timescale 1ns/1ps

module compute_tile_tb;

    // -----------------------------
    // Parameters (override via -P)
    // -----------------------------
    parameter integer ACT_WIDTH = 4;
    parameter integer ACC_WIDTH = 16;
    parameter integer N         = 2;

    // Big memory depth = MAX_K per row/col
    parameter integer MAX_K     = 8;

    // Total K to execute (must be <= MAX_K)
    parameter integer K_TOTAL   = 8;

    // Per-pass tile K (mm does K_TILE each pass)
    parameter integer K_TILE    = 2;

    // FIFO depths
    parameter integer ACT_FIFO_DEPTH = 8;
    parameter integer OUT_FIFO_DEPTH = 32;
    parameter integer PIPE_LAT       = 1;

    // -----------------------------
    // Clock/reset/control
    // -----------------------------
    reg clk;
    reg rst;
    reg start;

    // K_total is a *runtime* reg into DUT
    // width = clog2(MAX_K+1)
    reg [$clog2(MAX_K+1)-1:0] K_total;

    wire busy;
    wire done;

    // -----------------------------
    // Big memories
    // -----------------------------
    reg  [ACT_WIDTH-1:0] act_mem [0:N*MAX_K-1];
    reg  [ACT_WIDTH-1:0] w_mem   [0:N*MAX_K-1];
    wire [ACC_WIDTH-1:0] out_mem [0:N*N-1];

    integer i, j;
    integer outfile;

    // Clock
    always #5 clk = ~clk;

    // -----------------------------
    // DUT
    // -----------------------------
    compute_tile #(
        .ACT_WIDTH      (ACT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .N              (N),
        .ACT_FIFO_DEPTH (ACT_FIFO_DEPTH),
        .OUT_FIFO_DEPTH (OUT_FIFO_DEPTH),
        .K_TILE         (K_TILE),
        .MAX_K          (MAX_K),
        .PIPE_LAT       (PIPE_LAT)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .K_total (K_total),
        .busy    (busy),
        .done    (done),
        .act_mem (act_mem),
        .w_mem   (w_mem),
        .out_mem (out_mem)
    );

    // -----------------------------
    // Test sequence
    // -----------------------------
    initial begin
        $dumpfile("build/compute_tile_tb.vcd");
        $dumpvars(0, compute_tile_tb);

        outfile = $fopen("build/verilog_output.txt", "w");
        if (outfile == 0) begin
            $display("ERROR: cannot open build/verilog_output.txt");
            $finish;
        end

        // init
        clk     = 1'b0;
        rst     = 1'b0;
        start   = 1'b0;

        // drive runtime K from parameter
        // (truncate if needed; user should keep K_TOTAL <= MAX_K)
        K_total = K_TOTAL[$clog2(MAX_K+1)-1:0];

        // load memories
        // File format: one hex nibble per line (0..F) for int4
        $readmemh("tb/act.mem", act_mem);
        $readmemh("tb/w.mem",   w_mem);

        // reset
        #10 rst = 1'b1;
        #20;

        // start pulse
        start = 1'b1;
        #10;
        start = 1'b0;

        // wait for done
        wait (done == 1'b1);
        #20;

        // dump out_mem as PE[row][col] in row-major
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                $fdisplay(outfile, "PE[%0d][%0d]: %0h", i, j, out_mem[i*N + j]);
            end
        end

        $fclose(outfile);
        $finish;
    end

endmodule