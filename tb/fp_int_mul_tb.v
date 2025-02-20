module fp_int_mul_tb;

    // Parameters for the testbench
    parameter ACT_WIDTH = 16;
    parameter W_WIDTH = 4;
    parameter ACC_WIDTH = 32;

    // Testbench signals
    reg clk;
    reg rst;
    reg [ACT_WIDTH-1:0] activation;
    reg [W_WIDTH-1:0] weight;
    reg start;
    wire busy;
    wire sign_out;
    wire [4:0] exp_out;
    wire [14:0] mantissa_out;
    wire start_acc;

    // Instantiate the fp_int_mul module
    fp_int_mul #(
        .ACT_WIDTH(ACT_WIDTH),
        .W_WIDTH(W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .activation(activation),
        .weight(weight),
        .start(start),
        .busy(busy),
        .sign_out(sign_out),
        .exp_out(exp_out),
        .mantissa_out(mantissa_out),
        .start_acc(start_acc)
    );

    // Clock generation
    always begin
        #5 clk = ~clk; // Toggle clock every 5 time units
    end

    // Test stimulus
    initial begin
        $dumpfile("build/fp_int_mul.vcd");
        $dumpvars(0,fp_int_mul_tb);
        // Initialize signals
        clk = 0;
        rst = 0;
        start = 0;
        activation = 16'hC1A9; // FP16: -5.625 (sign = 1, exponent = 10000, mantissa = 0110101001)
        weight = 4'b0110; // INT4: 6 (binary 0110)

        // Reset the system
        #10 rst = 1; // Release reset
        // #10 rst = 0; 

        // Apply start pulse to trigger multiplication
        #10 start = 1; // Start multiplication
        #10 start = 0; // End start pulse

        // Wait for the operation to complete
        #35; // Wait a few cycles for computation to finish

        // Check the outputs
        $display("sign_out: %b", sign_out);
        $display("exp_out: %b", exp_out);
        $display("mantissa_out: %b", mantissa_out);
        $display("start_acc: %b", start_acc);

        // Verification of the outputs
        if (sign_out !== 1) begin
            $display("ERROR: sign_out is incorrect. Expected 1, got %b", sign_out);
        end else begin
            $display("sign_out is correct.");
        end

        // Verify the exponent (should be 10000 for exponent = 4)
        if (exp_out !== 5'b10000) begin
            $display("ERROR: exp_out is incorrect. Expected 10000, got %b", exp_out);
        end else begin
            $display("exp_out is correct.");
        end

        // Verify the mantissa (fixed-point representation of -33.75)
        if (mantissa_out !== 14'b10000111110110) begin
            $display("ERROR: mantissa_out is incorrect. Expected 10000111110110, got %b", mantissa_out);
        end else begin
            $display("mantissa_out is correct.");
        end
        
        #5 start = 1; // Start multiplication
        #10 start = 0; // End start pulse
        #40; // Wait a few cycles for computation to finish
        // Finish the simulation
        $finish;
    end

endmodule
