module fp_int_mac #(
    parameter ACT_WIDTH = 16,
    parameter W_WIDTH  = 4,
    parameter ACC_WIDTH = 32
)(
    input                  clk,
    input                  rst,
    input                  start,
    input [ACT_WIDTH-1:0]  activation,
    input [W_WIDTH-1:0]    weight,
    input  [4:0]           exp_min,
    input  [31:0]          fixed_point_acc,
    output [4:0]           exp_out,
    output [ACC_WIDTH-1:0] fixed_point_out,
    output                 done
);

// Intermediate signals between Multiplier and Accumulator
wire                    mul_done;
wire                    sign_out;
wire [4:0]              exp_out_mul;
wire [13:0]             mantissa_out;

// Accumulator signals
reg [4:0]               exp_min_reg;
reg                     acc_start;

// Instantiate the Multiplier Unit (fp16 × int4)
fp_int_mul #(
    .ACT_WIDTH(ACT_WIDTH),
    .W_WIDTH(W_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) mul_unit (
    .clk(clk),
    .rst(rst),
    .activation(activation),
    .weight(weight),
    .start(start),
    .busy(),
    .sign_out(sign_out),
    .exp_out(exp_out_mul),
    .mantissa_out(mantissa_out),
    .done(mul_done)
);

// Instantiate the Accumulator Unit
fp_int_acc acc_unit (
    .clk(clk),
    .rst(rst),
    .start(mul_done),
    .sign_in(sign_out),
    .exp_min(exp_min),
    .fixed_point_acc(fixed_point_acc),
    .exp_in(exp_out_mul),
    .fixed_point_in(mantissa_out),
    .exp_out(exp_out),
    .fixed_point_out(fixed_point_out),
    .done(done)
);

endmodule
