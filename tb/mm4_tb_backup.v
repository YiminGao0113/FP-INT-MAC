`timescale 1ns/1ps

module mm_tb;

    // ---- Parameters (adjust as needed) ----
    parameter ACT_WIDTH      = 4;     // INT4
    parameter ACC_WIDTH      = 16;
    parameter N              = 2;
    parameter K              = 2;
    parameter ACT_FIFO_DEPTH = 8;
    parameter W_FIFO_DEPTH   = 128;

    // 'precision' is unused in parallel INT path, but kept for act_fifo interface
    // set to 0 (or any fixed value your act_fifo tolerates)
    parameter [3:0] PRECISION_INIT = 4'd0;
    parameter [4:0] EXP_SET_INIT   = 5'd0;

    // ---- DUT I/O ----
    reg                          clk, rst, active;
    reg        [3:0]             precision;
    reg        [4:0]             exp_set;
    wire                         done;
    wire [4:0]                   exp_out [0:N*N-1];
    wire [ACC_WIDTH-1:0]         acc_out [N*N-1:0];

    // ---- Memories (parallel words now) ----
    reg [ACT_WIDTH-1:0] act_mem [0:N*K-1];   // N rows × K steps
    reg [ACT_WIDTH-1:0] w_mem   [0:N*K-1];   // N cols × K steps

    // ---- FIFO inputs to mm (N lanes) ----
    reg [ACT_WIDTH-1:0] act_din [0:N-1];
    reg [ACT_WIDTH-1:0] w_din   [0:N-1];

    reg  wr_en_act;
    reg  wr_en_w;

    integer k, r, l;
    integer outfile;

    // Clock
    always #5 clk = ~clk;

    // DUT
    mm #(
        .ACT_WIDTH      (ACT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .N              (N),
        .K              (K),
        .ACT_FIFO_DEPTH (ACT_FIFO_DEPTH)
        // .W_FIFO_DEPTH   (W_FIFO_DEPTH)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .active     (active),
        .ain    (act_din),
        .bin      (w_din),
        .wr_en_act  (wr_en_act),
        .wr_en_w    (wr_en_w),
        .done       (done),
        .acc_out    (acc_out)
    );

    initial begin
        $dumpfile("build/mm_tb.vcd");
        $dumpvars(0, mm_tb);

        outfile = $fopen("build/verilog_output.txt", "w");
        if (outfile == 0) begin
            $display("ERROR: cannot open build/verilog_output.txt");
            $finish;
        end

        // ---- Reset & init ----
        clk = 1;
        rst = 0;
        active = 0;
        precision = PRECISION_INIT;  // not used in parallel mode
        exp_set   = EXP_SET_INIT;    // not used; mm ties exp_out to 0

        // Clear FIFO inputs
        for (r = 0; r < N; r = r + 1) begin
            act_din[r] = {ACT_WIDTH{1'b0}};
            w_din[r]   = {ACT_WIDTH{1'b0}};
        end

        // ---- Load memories (parallel words) ----
        // Expect each line is an ACT_WIDTH-wide hex/dec value per element
        // act.mem layout: for k in [0..K-1], row r in [0..N-1] at index (r*K + k)
        // w.mem   layout: for k in [0..K-1], col c in [0..N-1] at index (c*K + k)
        $readmemh("tb/act.mem", act_mem);
        $readmemh("tb/w.mem",   w_mem);

        // Release reset
        #10 rst = 1; wr_en_act = 0; wr_en_w = 0;
        #20

        // ----------------------------------------------------------------
        // Push K steps of activations & weights into their FIFOs
        // ----------------------------------------------------------------
        wr_en_act = 1;
        wr_en_w   = 1;

        for (k = 0; k < K; k = k + 1) begin
            // Drive all N lanes for this step k
            for (r = 0; r < N; r = r + 1) begin
                act_din[r] = act_mem[r*K + k];  // row r uses A[r][k]
                w_din[r]   = w_mem  [r*K + k];  // column r uses B[k][r]
            end
            #10; // one push per cycle
        end

        // Stop writing into FIFOs
        wr_en_act = 0;
        wr_en_w   = 0;

        // ----------------------------------------------------------------
        // Kick the systolic for K cycles (no bit-serial; exactly K steps)
        // ----------------------------------------------------------------
        #10;
        for (k = 0; k < K; k = k + 1) begin
            active = 1;
            #10;
        end
        active = 0;

        // Wait for done
        wait (done);  // Wait for 'done' signal to become high

        // Optionally wait one cycle after 'done' is high
        #50;

        $fclose(outfile);
        $finish;
    end
    
    always @(posedge done) begin
        // $display("==== [DONE asserted] Checking Outputs ====");
        // for (l = 0; l < N*N; l= l + 1) begin
        //     if (acc_out[l] !== expected_out[l])
        //         $display("Mismatch at PE[%0d][%0d]: got %h, expected %h", l/N, l%N, acc_out[l], expected_out[l]);
        //     else
        //         $display("PE[%0d][%0d] correct: %h", l/N, l%N, acc_out[l]);
        // end
        // $display("==========================================");
        $fdisplay(outfile, "==== [DONE asserted] Checking Outputs ====");
        for (l = 0; l < N*N; l = l + 1) begin
            // if (acc_out[l] !== expected_out[l])
                // $fdisplay(outfile, "Mismatch at PE[%0d][%0d]: got %h, expected %h", l/N, l%N, acc_out[l], expected_out[l]);
            // else
            $fdisplay(outfile, "PE[%0d][%0d]: %h", l/N, l%N, acc_out[l]);
        end
        $fdisplay(outfile, "==========================================");
    end

endmodule
