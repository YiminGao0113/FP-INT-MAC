`timescale 1ns/1ps

module fifo_tb;

    reg clk;
    reg rst;
    reg wr_en;
    reg rd_en;
    reg din;
    wire dout;
    wire full;
    wire empty;

    // Instantiate the FIFO
    fifo uut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .din(din),
        .dout(dout),
        .precision(4),
        .full(full),
        .empty(empty)
    );

    // Clock generation
    always #5 clk = ~clk;

    integer i;

    initial begin
        $display("Starting FIFO test...");
        $dumpfile("build/fifo_tb.vcd");
        $dumpvars(0, fifo_tb);

        clk = 0;
        rst = 1;
        wr_en = 0;
        rd_en = 0;
        din = 0;

        // Reset
        #10;
        rst = 0;

        // Write pattern: 1, 0, 1, 0, ...
        for (i = 0; i < 32; i = i + 1) begin
            @(posedge clk);
            din = i % 2;
            wr_en = 1;
            rd_en = 0;
        end

        @(posedge clk);
        wr_en = 0;

        // Read back
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            rd_en = 1;
        end

        @(posedge clk);
        rd_en = 0;

        $display("Finished FIFO test.");
        $finish;
    end

endmodule
