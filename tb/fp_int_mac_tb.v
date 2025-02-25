`timescale 1ns/1ps

module fp_int_mac_tb;

    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;

    reg clk;
    reg rst;
    reg valid;
    reg [3:0] precision;
    reg set;
    reg [ACT_WIDTH-1:0] act;
    reg w;
    reg [4:0] exp_set;
    reg [31:0] fixed_point_acc;
    wire [4:0] exp_out;
    wire [ACC_WIDTH-1:0] fixed_point_out;
    wire done;

    // Expected values
    reg [4:0] expected_exp;
    reg [31:0] expected_fixed_point;

    // Instantiate the MAC unit
    fp_int_mac #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .precision(precision),
        .set(set),
        .act(act),
        .w(w),
        .exp_set(exp_set),
        .fixed_point_acc(fixed_point_acc),
        .exp_out(exp_out),
        .fixed_point_out(fixed_point_out),
        .done(done)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Monitor results when done goes high
    always @(posedge done) begin
        $display("Done signal detected! Time: %0t | exp_out: %b | fixed_point_out: %b", $time, exp_out, fixed_point_out);
        
        // Verification of the outputs
        if (exp_out !== expected_exp) begin
            $display("ERROR: exp_out is incorrect. Expected %b, got %b", expected_exp, exp_out);
        end else begin
            $display("exp_out is correct.");
        end

        if (fixed_point_out !== expected_fixed_point) begin
            $display("ERROR: fixed_point_out is incorrect. Expected %b, got %b", expected_fixed_point, fixed_point_out);
        end else begin
            $display("fixed_point_out is correct.");
        end
    end

    // Test stimulus
    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        valid = 0;
        precision = 4;
        set = 0;
        act = 16'b0100010101101001; // Example FP16 value
        w = 0;
        exp_set = 5'b10000; // Example exponent min
        fixed_point_acc = 32'b00000000000000000000000000000010; // Start accumulator at 0

        // Create VCD file for GTKWave
        $dumpfile("build/fp_int_mac.vcd");
        $dumpvars(0, fp_int_mac_tb);
            
        // Apply reset
        #10 rst = 0;
        #10 rst = 1;

        #10 set = 1;
        #10 set = 0;

        // Start the first MAC operation
        #15 valid = 1;
        repeat (4) begin //w:0101
            #10 w = ~w;
        end
        expected_exp = 5'b10000;
        expected_fixed_point = 32'b011011000011100;
        act = 16'b0100010101101010; // Example FP16 value
        repeat (4) begin
            #10 w = ~w;
        end
        expected_fixed_point = 32'b11011000100110;
        act = 16'b0100100000100001; // Example FP16 value
        repeat (4) begin
            #10 w = ~w;
        end
        expected_fixed_point = 32'b101001010010110;
        #10 valid = 0;

        #80

        // Start another MAC operation with different values
        act = 16'b0100101010101010; // Different FP16 value
        w = 1;
        valid = 1; //1010
        expected_fixed_point = 32'b11111111111111111100101010110010;

        #10 w = ~w;
        #10 w = ~w;
        #10 w = ~w;
        #10 valid = 0;
        #10 valid = 1;

        w = 0;
        #20
        expected_fixed_point = 32'b10;
        #60

        // End simulation
        $finish;
    end

endmodule
