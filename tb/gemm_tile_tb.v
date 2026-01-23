`timescale 1ns/1ps

module gemm_tile_tb;

    // -----------------------------
    // Parameters (override via -P)
    // -----------------------------
    parameter integer ACT_WIDTH = 4;
    parameter integer ACC_WIDTH = 16;

    // Full GEMM size (square): N_FULL x N_FULL
    parameter integer N_FULL    = 8;

    // compute_tile tile size: TILE_N x TILE_N
    parameter integer TILE_N    = 4;

    // Big memory depth = MAX_K per row/col
    parameter integer MAX_K     = 8;

    // Total K to execute (must be <= MAX_K)
    parameter integer K_TOTAL   = 8;

    // Per-pass K inside compute_tile (must divide K_TOTAL for simplified compute_tile)
    parameter integer K_TILE    = 4;

    // FIFO depths (passed through to compute_tile)
    parameter integer ACT_FIFO_DEPTH = 8;
    parameter integer OUT_FIFO_DEPTH = 32;
    parameter integer PIPE_LAT       = 1;

    // -----------------------------
    // Clock/reset/control
    // -----------------------------
    reg clk;
    reg rst;
    reg start;

    // runtime K_total into DUT (width = clog2(MAX_K+1))
    reg [$clog2(MAX_K+1)-1:0] K_total;

    wire busy;
    wire done;

    // -----------------------------
    // Big memories (full problem)
    // -----------------------------
    reg  [ACT_WIDTH-1:0]  act_mem_full [0:N_FULL*MAX_K-1];
    reg  [ACT_WIDTH-1:0]  w_mem_full   [0:N_FULL*MAX_K-1];
    wire [ACC_WIDTH-1:0]  out_mem_full [0:N_FULL*N_FULL-1];

    integer i, j;
    integer outfile;

    // Clock
    always #5 clk = ~clk;

    // -----------------------------
    // DUT
    // -----------------------------
    gemm_tile #(
        .ACT_WIDTH      (ACT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .N_FULL         (N_FULL),
        .TILE_N         (TILE_N),
        .MAX_K          (MAX_K),
        .K_TILE         (K_TILE),
        .ACT_FIFO_DEPTH (ACT_FIFO_DEPTH),
        .OUT_FIFO_DEPTH (OUT_FIFO_DEPTH),
        .PIPE_LAT       (PIPE_LAT)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .K_total      (K_total),
        .busy         (busy),
        .done         (done),
        .act_mem_full (act_mem_full),
        .w_mem_full   (w_mem_full),
        .out_mem_full (out_mem_full)
    );

    // -----------------------------
    // Test sequence
    // -----------------------------
    initial begin
        $dumpfile("build/gemm_tile_tb.vcd");
        $dumpvars(0, gemm_tile_tb);

        outfile = $fopen("build/verilog_output.txt", "w");
        if (outfile == 0) begin
            $display("ERROR: cannot open build/verilog_output.txt");
            $finish;
        end

        // init
        clk     = 1'b0;
        rst     = 1'b0;
        start   = 1'b0;

        // drive runtime K from parameter (truncate if needed)
        K_total = K_TOTAL[$clog2(MAX_K+1)-1:0];

        // load memories
        // Format: one hex nibble per line (0..F), total N_FULL*MAX_K lines each
        $readmemh("tb/act.mem", act_mem_full);
        $readmemh("tb/w.mem",   w_mem_full);

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

        // dump full output as PE[row][col] in row-major
        for (i = 0; i < N_FULL; i = i + 1) begin
            for (j = 0; j < N_FULL; j = j + 1) begin
                $fdisplay(outfile, "PE[%0d][%0d]: %0h", i, j, out_mem_full[i*N_FULL + j]);
            end
        end

        $fclose(outfile);
        $finish;
    end

endmodule