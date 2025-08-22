`timescale 1ns/1ps

module tb_systolic_array;

    localparam D_W       = 4;
    localparam ACC_WIDTH = 16;
    localparam N         = 2;

    reg clk, rst, en;
    reg  [D_W-1:0] a_in [0:N-1];       // row inputs
    reg  [D_W-1:0] b_in [0:N-1];       // column inputs
    wire [ACC_WIDTH-1:0] c_out [0:N-1][0:N-1]; // 2D outputs

    // Instantiate DUT
    systolic_array #(
        .D_W(D_W),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .a_in(a_in),
        .b_in(b_in),
        .c_out(c_out)
    );

    // Clock generation
    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        clk = 0;
        rst = 1;
        en  = 0;
        #10;

        rst = 0;
        #16;
        en  = 1;

        // First inputs
        // A row0=1,row1=3
        // B col0=5,col1=6
        a_in[0] = 4'd1;
        b_in[0] = 4'd5;

        #10;
        a_in[0] = 4'd2;
        b_in[0] = 4'd7;
        a_in[1] = 4'd3;
        b_in[1] = 4'd6;

        #10;
        en  = 0;
        // Next inputs
        // A row0=2,row1=4
        // B col0=7,col1=8
        a_in[1] = 4'd4;
        b_in[1] = 4'd8;

        #10;
        en = 0;  // stop accumulating

        #50;

        // Display accumulated outputs
        $display("C[0][0] = %d (expected 19)", c_out[0][0]);
        $display("C[0][1] = %d (expected 22)", c_out[0][1]);
        $display("C[1][0] = %d (expected 43)", c_out[1][0]);
        $display("C[1][1] = %d (expected 50)", c_out[1][1]);

        #20;
        $finish;
    end

endmodule
