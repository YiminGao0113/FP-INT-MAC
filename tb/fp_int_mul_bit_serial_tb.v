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
        // Change w each cycle
        repeat (10) begin
            #10 w = ~w;
        end
        #10 valid = 0;
        #30 valid = 1;
        #10 w = 0;
        #35 w = 1;
        #10 w = 0;
        // End simulation
        #50 $finish;
    end

endmodule
