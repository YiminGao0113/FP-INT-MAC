`timescale 1ns/1ps

module systolic_tb;

    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;
    parameter N = 2;

    reg clk, rst, active;
    reg [3:0] precision;
    reg [4:0] exp_set;
    reg [ACT_WIDTH-1:0] act_in [N-1:0];
    reg w_in [N-1:0];
    wire done;
    wire [4:0] exp_out [N*N-1:0];
    wire [ACC_WIDTH-1:0] acc_out [N*N-1:0];

    // Expected outputs for each PE
    reg [ACC_WIDTH-1:0] expected_out [0:N*N-1];

    initial begin
        expected_out[0] = 32'hFFFF9000;  // PE[0][0]
        expected_out[1] = 32'hFFFF9000;  // PE[0][1]
        expected_out[2] = 32'hFFFFAC00;  // PE[1][0]
        expected_out[3] = 32'hFFFFAC00;  // PE[1][1]
    end



    // Instantiate DUT
    systolic #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .active(active),
        .precision(precision),
        .act_in(act_in),
        .w_in(w_in),
        .exp_set(exp_set),
        .done(done),
        .exp_out(exp_out),
        .acc_out(acc_out)
    );

    // Clock
    always #5 clk = ~clk;

    integer i;

    initial begin
        $dumpfile("build/systolic.vcd");
        $dumpvars(0, systolic_tb);

        clk = 1;
        rst = 0;
        active = 0;
        precision = 4'd4;
        exp_set = 5'd15;

        #20 rst = 1;
        #10

        // Feed first row of A and column of B
        act_in[0] = 16'h3C00;  // 1.0
        act_in[1] = 16'h4000;  // 2.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b1;
        // #5
        active = 1;
        #5

        #40
        act_in[0] = 16'h4200;  // 3.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b1;

        #40
        act_in[0] = 16'h0000;  // 3.0
        act_in[1] = 16'h3C00;  // 2.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b1;
        

        active = 0;
        #200

        $finish;
    end

always @(posedge done) begin
    $display("==== [DONE asserted] Checking Outputs ====");
    for (i = 0; i < N*N; i = i + 1) begin
        if (acc_out[i] !== expected_out[i])
            $display("Mismatch at PE[%0d][%0d]: got %h, expected %h", i/N, i%N, acc_out[i], expected_out[i]);
        else
            $display("PE[%0d][%0d] correct: %h", i/N, i%N, acc_out[i]);
    end
    $display("==========================================");
end

endmodule
// pe [0, 0] - 11111111111111111001000000000000 (FFFF9000)
// pe [0, 1] - 11111111111111111001000000000000 (FFFF9000)
// pe [1, 0] - 11111111111111111010110000000000 (FFFFAC00)
// pe [1, 1] - 11111111111111111010110000000000 (FFFFAC00)