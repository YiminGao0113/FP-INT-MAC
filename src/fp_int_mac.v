module fp_int_mac #(
    parameter ACT_WIDTH = 16,
    parameter ACC_WIDTH = 32
)(
    input                       clk,
    input                       rst,
    input                       valid,
    input [3:0]                 precision,
    // input                   set,
    input [ACT_WIDTH-1:0]       act,
    input                       w,
    input [4:0]                 exp_set,
    input [31:0]                fixed_point_acc,
    output [4:0]                exp_out,
    output [ACC_WIDTH-1:0]      fixed_point_out,
    output                      done,
    output                      _valid,
    output [ACT_WIDTH-1:0]      _act,
    output                      _w
);

// Intermediate signals between Multiplier and Accumulator
wire                    start_acc;
wire                    sign_out;
wire [4:0]              exp_out_mul;
wire [13:0]             mantissa_out;

// Instantiate the Multiplier Unit (fp16 × int4)
fp_int_mul #(
    .ACT_WIDTH(ACT_WIDTH)
) mul_unit (
    .clk(clk),
    .rst(rst),
    .act(act),
    .w(w),
    .valid(valid),
    .precision(precision),
    .sign_out(sign_out),
    .exp_out(exp_out_mul),
    .mantissa_out(mantissa_out),
    .start_acc(start_acc),
    ._valid(_valid),
    ._act(_act),
    ._w(_w)
);

// Instantiate the Accumulator Unit
fp_int_acc acc_unit (
    .clk(clk),
    .rst(rst),
    // .valid(valid),
    .start(start_acc),
    .sign_in(sign_out),
    .exp_set(exp_set),
    .fixed_point_acc(fixed_point_acc),
    .exp_in(exp_out_mul),
    .fixed_point_in(mantissa_out),
    .exp_out(exp_out),
    .fixed_point_out(fixed_point_out),
    .done(done)
);

endmodule
