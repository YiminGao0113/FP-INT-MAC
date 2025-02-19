module fp_int_mac_tb;

    // Parameters
    parameter ACT_WIDTH = 16;
    parameter W_WIDTH = 4;
    parameter ACC_WIDTH = 32;

    // Testbench signals
    reg clk;
    reg rst;
    reg start;
    reg [ACT_WIDTH-1:0] activation;
    reg [W_WIDTH-1:0] weight;
    reg [4:0] exp_min;
    reg [31:0] fixed_point_acc;
    wire [4:0] exp_out;
    wire [ACC_WIDTH-1:0] fixed_point_out;
    wire done;

    // Instantiate the MAC unit
    fp_int_mac #(
        .ACT_WIDTH(ACT_WIDTH),
        .W_WIDTH(W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .activation(activation),
        .weight(weight),
        .exp_min(exp_min),
        .fixed_point_acc(fixed_point_acc),
        .exp_out(exp_out),
        .fixed_point_out(fixed_point_out),
        .done(done)
    );

    // Clock generation
    always begin
        #5 clk = ~clk; // Toggle clock every 5 time units
    end

    // Test stimulus
    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        start = 0;
        activation = 16'b0100010101101001; // Example FP16 value
        weight = 4'b0110; // Example INT4 value
        exp_min = 5'b10000; // Example exponent min
        fixed_point_acc = 32'b00000000000000000000000000000010; // Start accumulator at 0

        // Create VCD file for GTKWave
        $dumpfile("build/fp_int_mac.vcd");
        $dumpvars(0, fp_int_mac_tb);

        // Apply reset
        #10 rst = 0;
        #10 rst = 1;

        // Start the first MAC operation
        #10 start = 1;
        #10 start = 0;

        // Wait for MAC operation to complete
        wait(done);
        
        // Display results
        $display("MAC Operation Completed");
        $display("exp_out: %b", exp_out);
        $display("fixed_point_out: %b", fixed_point_out);

        // // Verification
        // if (exp_out !== 5'bXXXXX) // Replace XXXXX with expected exponent
        //     $display("ERROR: exp_out is incorrect. Expected XXXXX, got %b", exp_out);
        // else 
        //     $display("exp_out is correct.");

        // if (fixed_point_out !== 32'bXXXXXXXXXXXX) // Replace XXXXXX with expected value
        //     $display("ERROR: fixed_point_out is incorrect. Expected XXXXXX, got %b", fixed_point_out);
        // else 
        //     $display("fixed_point_out is correct.");

        // Start another MAC operation with different values
        activation = 16'b0100101010101010; // Different FP16 value
        weight = 4'b0101; // Different INT4 value
        start = 1;
        #10 start = 0;

        // Wait for completion
        wait(done);
        $display("Second MAC Operation Completed");

        // End simulation
        $finish;
    end

endmodule
