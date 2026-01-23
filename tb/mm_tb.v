`timescale 1ns/1ps

module mm_tb;

    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;
    parameter N = 2;
    parameter K = 2;
    parameter P = 4;
    parameter EXP = 5'd15;

    parameter ACT_FIFO_DEPTH = 8;
    parameter W_FIFO_DEPTH   = 128;
    parameter OUT_FIFO_DEPTH = 64;
    parameter ACC_BINPT      = 10;

    reg clk, rst, active;
    reg [3:0] precision;
    reg [4:0] exp_set;

    // DUT inputs
    reg [ACT_WIDTH-1:0] act_din [N-1:0];
    reg                 w_din   [N-1:0];
    reg                 wr_en_act;
    reg                 wr_en_w;

    // DUT outputs
    wire                 done;
    wire [4:0]           exp_out [N*N-1:0];
    wire [ACC_WIDTH-1:0] acc_out [N*N-1:0];

    // output FIFO interface (per-row)
    reg  [N-1:0] out_rd_en;
    wire [N-1:0] out_empty;
    wire [N-1:0] out_full;
    wire [15:0]  out_dout [N-1:0];

    // memories
    reg [ACT_WIDTH-1:0] act_mem [0:N*K-1];
    reg                 w_mem   [0:N*K*P-1];

    integer outfile;
    integer k, r, p;
    integer rr, cc;

    // clock
    always #5 clk = ~clk;

    // DUT
    mm #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N),
        .K(K),
        .ACT_FIFO_DEPTH(ACT_FIFO_DEPTH),
        .W_FIFO_DEPTH(W_FIFO_DEPTH),
        .OUT_FIFO_DEPTH(OUT_FIFO_DEPTH),
        .ACC_BINPT(ACC_BINPT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .active(active),
        .precision(precision),
        .exp_set(exp_set),
        .act_din(act_din),
        .w_din(w_din),
        .wr_en_act(wr_en_act),
        .wr_en_w(wr_en_w),
        .done(done),
        .exp_out(exp_out),
        .acc_out(acc_out),

        .out_rd_en(out_rd_en),
        .out_empty(out_empty),
        .out_full(out_full),
        .out_dout(out_dout)
    );

    // reset task (matches your style)
    task do_reset;
    begin
        rst = 1;
        #10;
        rst = 0;
        #10;
        rst = 1;
        #10;
    end
    endtask

    // Pop one element from row rr; sample dout next cycle (safe)
    task pop_and_log(input integer row_idx, input integer col_idx);
    begin
        // wait until not empty (avoid KeyError + avoid reading garbage)
        while (out_empty[row_idx]) begin
            #10;
        end

        // assert rd_en for 1 cycle
        out_rd_en[row_idx] = 1'b1;
        #10;
        out_rd_en[row_idx] = 1'b0;

        // sample next cycle (works for registered-read FIFO)
        #10;

        // OLD format for python: PE[i][j]: 0x....
        $fdisplay(outfile, "PE[%0d][%0d]: 0x%h", row_idx, col_idx, out_dout[row_idx]);
    end
    endtask

    initial begin
        $dumpfile("build/mm_tb.vcd");
        $dumpvars(0, mm_tb);

        outfile = $fopen("build/verilog_output.txt", "w");
        if (outfile == 0) begin
            $display("❌ ERROR: Failed to open output file.");
            $finish;
        end

        // init
        clk = 0;
        active = 0;
        precision = P;
        exp_set = EXP;
        wr_en_act = 0;
        wr_en_w   = 0;
        out_rd_en = '0;

        $readmemh("tb/act.mem", act_mem);
        $readmemh("tb/w.mem", w_mem);

        do_reset();

        // -------------------------
        // preload activation FIFOs
        // -------------------------
        wr_en_act = 1;
        for (k = 0; k < K; k = k + 1) begin
            for (r = 0; r < N; r = r + 1) begin
                act_din[r] = act_mem[r*K + k];
            end
            #10;
        end
        wr_en_act = 0;
        #10;

        // -------------------------
        // preload weight FIFOs (bit-serial)
        // -------------------------
        wr_en_w = 1;
        for (k = 0; k < K; k = k + 1) begin
            for (p = 0; p < precision; p = p + 1) begin
                for (r = 0; r < N; r = r + 1) begin
                    w_din[r] = w_mem[(r*K + k)*precision + p];
                end
                #10;
            end
        end
        wr_en_w = 0;
        #20;

        // -------------------------
        // run compute
        // -------------------------
        for (k = 0; k < K*precision; k = k + 1) begin
            active = 1;
            #10;
        end
        active = 0;

        // wait for done
        wait(done);
        #20;

        // read outputs from FIFOs and log (row-major order)
        $fdisplay(outfile, "==== [DONE asserted] FIFO Outputs (FP16 hex) ====");
        for (rr = 0; rr < N; rr = rr + 1) begin
            for (cc = 0; cc < N; cc = cc + 1) begin
                pop_and_log(rr, cc);
            end
        end
        $fdisplay(outfile, "===============================================");

        $fclose(outfile);
        $finish;
    end

endmodule