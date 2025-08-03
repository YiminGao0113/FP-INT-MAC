`timescale 1ns/1ps

module int_mac_tb;

    parameter ACT_WIDTH = 4;
    parameter ACC_WIDTH = 16;

    reg clk;
    reg rst;
    reg valid;
    reg [3:0] precision;
    reg signed [ACT_WIDTH-1:0] act;
    reg w;
    reg signed [ACC_WIDTH-1:0] fixed_point_acc;

    wire signed [ACC_WIDTH-1:0] fixed_point_out;
    wire done;
    wire SA_done;
    wire _valid;
    wire [ACT_WIDTH-1:0] _act;
    wire _w;

    // Instantiate the MAC unit
    int_mac #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .precision(precision),
        .act(act),
        .w(w),
        .fixed_point_acc(fixed_point_acc),
        .fixed_point_out(fixed_point_out),
        .done(done),
        .SA_done(SA_done),
        ._valid(_valid),
        ._act(_act),
        ._w(_w)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Observe output
    always @(posedge done) begin
        $display("[Time %0t] DONE: act = %0d, final fixed_point_out = %0d", $time, act, fixed_point_out);
    end

    initial begin
        // VCD dump
        $dumpfile("build/int_mac.vcd");
        $dumpvars(0, int_mac_tb);

        // Initialize
        clk = 0;
        rst = 1;
        valid = 0;
        precision = 4;
        act = 0;
        w = 0;
        fixed_point_acc = 0;

        // Reset
        #10 rst = 0;
        #10 rst = 1;
        // Test 1: act = -3 (1101), weight = 0011 → +3
        act = -3;
        fixed_point_acc = 0;
        #20

        valid = 1;

        w = 1; #10;
        w = 1; #10;
        w = 0; #10;
        w = 0; #10;

        valid = 0; #20;

        // Test 2: act = 5 (0101), weight = 1110 → -2
        act = 5;
        fixed_point_acc = fixed_point_out; // chain previous result
        valid = 1;

        w = 0; #10;
        w = 1; #10;
        w = 1; #10;
        w = 1; #10;

        valid = 0; #20;

        // Test 3: act = -8 (1000), weight = 0111 → 7
        act = -8;
        fixed_point_acc = fixed_point_out;
        valid = 1;

        w = 1; #10;
        w = 1; #10;
        w = 1; #10;
        w = 0; #10;

        valid = 0; #40;

        // Finish
        $display("Simulation complete.");
        $finish;
    end

endmodule
