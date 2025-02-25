`timescale 1ns/1ps

module fp_int_mul_bit_serial_tb;

    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;

    reg clk;
    reg rst;
    reg [ACT_WIDTH-1:0] act;
    reg w;
    reg valid;
    reg set;
    reg [3:0] precision;
    
    wire sign_out;
    wire [4:0] exp_out;
    wire [13:0] mantissa_out;
    wire start_acc;

    // Expected values
    reg expected_sign;
    reg [4:0] expected_exp;
    reg [13:0] expected_mantissa;

    // Instantiate the module under test
    fp_int_mul_bit_serial #(ACT_WIDTH, ACC_WIDTH) uut (
        .clk(clk),
        .rst(rst),
        .act(act),
        .w(w),
        .valid(valid),
        .set(set),
        .precision(precision),
        .sign_out(sign_out),
        .exp_out(exp_out),
        .mantissa_out(mantissa_out),
        .start_acc(start_acc)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Monitor results when start_acc goes high
    always @(posedge start_acc) begin
        $display("Start_acc detected! Time: %0t | sign_out: %b | exp_out: %b | mantissa_out: %b", $time, sign_out, exp_out, mantissa_out);
        
        // Verification of the outputs
        if (sign_out !== expected_sign) begin
            $display("ERROR: sign_out is incorrect. Expected %b, got %b", expected_sign, sign_out);
        end else begin
            $display("sign_out is correct.");
        end

        if (exp_out !== expected_exp) begin
            $display("ERROR: exp_out is incorrect. Expected %b, got %b", expected_exp, exp_out);
        end else begin
            $display("exp_out is correct.");
        end

        if (mantissa_out !== expected_mantissa) begin
            $display("ERROR: mantissa_out is incorrect. Expected %b, got %b", expected_mantissa, mantissa_out);
        end else begin
            $display("mantissa_out is correct.");
        end
    end

    initial begin
        // Create VCD file for GTKWave
        $dumpfile("build/fp_int_mul_bit_serial.vcd");
        $dumpvars(0, fp_int_mul_bit_serial_tb);

        // Initialize signals
        clk = 0;
        rst = 0;
        act = 16'h1234; // Example fixed activation value
        w = 0;
        valid = 0;
        set = 0;
        precision = 4;

        expected_sign = 0;
        expected_exp = 5'b00100;
        expected_mantissa = 14'b001111100000100;

        // Apply reset
        #10 rst = 1;
        #10 rst = 0;
        #10 rst = 1;

        // Set precision (enable set for one cycle)
        #10 set = 1;
        #10 set = 0;
        
        // Start simulation
        #10 valid = 1;
        #10 w = ~w;
        #10 w = ~w;
        #10 w = ~w;
        #5 act = 16'hf234;
        #5 w = ~w;
        expected_sign = 1;
        expected_exp = 5'b11100;
        // Change w each cycle
        repeat (4) begin
            #10 w = ~w;
        end
        #10 valid = 0;
        #30 valid = 1;
        expected_sign = 1;
        expected_mantissa = 14'b0;
        #10 w = 0;
        #35 w = 1;
        expected_sign = 0;
        #10 w = 0;
        // End simulation
        #50 $finish;
    end

endmodule
