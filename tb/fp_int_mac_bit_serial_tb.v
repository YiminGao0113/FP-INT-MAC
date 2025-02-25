module fp_int_mac_bit_serial_tb;

    // Parameters
    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;

    // Testbench signals
    reg clk;
    reg rst;
    reg valid;
    reg [3:0] precision;
    reg set;
    reg [ACT_WIDTH-1:0] act;
    reg w;
    reg [4:0] exp_min;
    reg [31:0] fixed_point_acc;
    wire [4:0] exp_out;
    wire [ACC_WIDTH-1:0] fixed_point_out;
    wire done;

    // Instantiate the MAC unit
    fp_int_mac_bit_serial #(
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
        .exp_min(exp_min),
        .fixed_point_acc(fixed_point_acc),
        .exp_out(exp_out),
        .fixed_point_out(fixed_point_out),
        .done(done)
    );

    // Clock generation
    always #5 clk = ~clk; // Toggle clock every 5 time units

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
        exp_min = 5'b10000; // Example exponent min
        fixed_point_acc = 32'b00000000000000000000000000000010; // Start accumulator at 0

        // Create VCD file for GTKWave
        $dumpfile("fp_int_mac_bit_serial.vcd");
        $dumpvars(0, fp_int_mac_bit_serial_tb);
            
        // Apply reset
        #10 rst = 0;
        #10 rst = 1;

        #10 set = 1;
        #10 set = 0;

        // Start the first MAC operation
        #15 valid = 1;
        repeat (10) begin
            #10 w = ~w;
        end
        #10 valid = 0;

        #80

        // Start another MAC operation with different values
        act = 16'b0100101010101010; // Different FP16 value
        w = 1;
        valid = 1;
        #10 w = ~w;
        #10 w = ~w;
        #10 w = ~w;
        #5 act = 16'b1011111010000000; // Different FP16 value
        #5 w = ~w;
        #5 w = 1;
        valid = 1;
        repeat (4) begin
            #10 w = ~w;
        end

        #10 valid = 0;
        #10 valid = 1;
        w = 0;
        #80

        // End simulation
        $finish;
    end

endmodule
