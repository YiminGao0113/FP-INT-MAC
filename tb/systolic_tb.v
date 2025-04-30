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
        $dumpfile("tb_systolic.vcd");
        $dumpvars(0, systolic_tb);

        clk = 1;
        rst = 0;
        active = 0;
        precision = 4'd4;
        exp_set = 5'd15;

        #20 rst = 1;
        #5 

        // Feed first row of A and column of B
        act_in[0] = 16'h3C00;  // 1.0
        act_in[1] = 16'h4000;  // 2.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b0;
        #5
        active = 1;

        #40
        act_in[0] = 16'h4200;  // 3.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b1;

        #40
        act_in[0] = 16'h0000;  // 3.0
        act_in[1] = 16'h0010;  // 2.0
        w_in[0]   = 1'b1;
        w_in[1]   = 1'b1;
        

        active = 0;
        #100 


        #500
        // Wait for done
        // wait (done);
        // $display("Computation complete.");
        // for (i = 0; i < N*N; i = i + 1)
        //     $display("acc_out[%0d] = %d", i, acc_out[i]);

        $finish;
    end

endmodule
