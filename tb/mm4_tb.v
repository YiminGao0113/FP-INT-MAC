`timescale 1ns/1ps

module mm_tb;

    parameter ACT_WIDTH      = 4;
    parameter ACC_WIDTH      = 16;
    parameter N              = 2;
    parameter K              = 2;
    parameter ACT_FIFO_DEPTH = 8;

    reg clk, rst, active;
    reg wr_en_act, wr_en_w;

    reg [ACT_WIDTH-1:0] act_din [0:N-1];
    reg [ACT_WIDTH-1:0] w_din   [0:N-1];

    // Output FIFO interface
    reg  [N-1:0]         out_rd_en;
    wire [N-1:0]         out_empty;
    wire [N-1:0]         out_full;
    wire [ACC_WIDTH-1:0] out_dout [N-1:0];

    wire done;

    // Memories
    reg [ACT_WIDTH-1:0] act_mem [0:N*K-1];
    reg [ACT_WIDTH-1:0] w_mem   [0:N*K-1];

    integer k, r, c;
    integer outfile;

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    mm #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N),
        .K(K),
        .ACT_FIFO_DEPTH(ACT_FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .active(active),
        .ain(act_din),
        .bin(w_din),
        .wr_en_act(wr_en_act),
        .wr_en_w(wr_en_w),
        .done(done),

        .out_rd_en(out_rd_en),
        .out_empty(out_empty),
        .out_full(out_full),
        .out_dout(out_dout)
    );

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        $dumpfile("build/mm_tb.vcd");
        $dumpvars(0, mm_tb);

        outfile = $fopen("build/verilog_output.txt", "w");

        clk = 0;
        rst = 0;
        active = 0;
        wr_en_act = 0;
        wr_en_w = 0;
        out_rd_en = '0;

        for (r = 0; r < N; r = r + 1) begin
            act_din[r] = 0;
            w_din[r]   = 0;
        end

        $readmemh("tb/act.mem", act_mem);
        $readmemh("tb/w.mem",   w_mem);

        // Reset
        #10 rst = 1;
        #10;

        // --------------------------------------------------------
        // Load activation + weight FIFOs
        // --------------------------------------------------------
        wr_en_act = 1;
        wr_en_w   = 1;

        for (k = 0; k < K; k = k + 1) begin
            for (r = 0; r < N; r = r + 1) begin
                act_din[r] = act_mem[r*K + k];
                w_din[r]   = w_mem[r*K + k];
            end
            #10;
        end

        wr_en_act = 0;
        wr_en_w   = 0;

        // --------------------------------------------------------
        // Run systolic (exactly K cycles)
        // --------------------------------------------------------
        #10;
        for (k = 0; k < K; k = k + 1) begin
            active = 1;
            #10;
        end
        active = 0;

      #200;
        // --------------------------------------------------------
        // Drain output FIFOs: N values per row
        // --------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            wait (!out_empty[r]);
            out_rd_en[r] = 1'b1;
            for (c = 0; c < N; c = c + 1) begin
                #10;
                $fdisplay(outfile, "PE[%0d][%0d]: %04h", r, c, out_dout[r]);
            end
            out_rd_en[r] = 1'b0;
        end

        $fclose(outfile); 
        $finish;
    end

endmodule