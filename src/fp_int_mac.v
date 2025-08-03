module int_mac #(
    parameter ACT_WIDTH = 4,
    parameter ACC_WIDTH = 16
)(
    input                       clk,
    input                       rst,
    input                       valid,
    input [3:0]                 precision,           // Bit-serial precision (e.g., 4)
    input signed [ACT_WIDTH-1:0] act,                // Full INT4 activation
    input                       w,                   // 1-bit serial weight input (LSB to MSB)
    input signed [ACC_WIDTH-1:0] fixed_point_acc,    // Initial accumulator state (external reg)

    output signed [ACC_WIDTH-1:0] fixed_point_out,   // Final accumulated result
    output                      done,                // One-shot signal after accumulation
    output                      SA_done,             // Used to indicate systolic array step done
    output                      _valid,              // Valid signal aligned with output
    output [ACT_WIDTH-1:0]      _act,                // Aligned activation
    output                      _w                   // Aligned weight bit
);

// ────────────── Intermediate signals ──────────────
wire        start_acc;      // Asserted at final cycle of MAC
wire        sign_out;       // XOR(act_sign, weight_sign)
wire signed [ACC_WIDTH-1:0] mantissa_out; // MAC output

// ────────────── Instantiate INT4 × INT4 MAC Unit ──────────────
int4_bitserial_mul #(
    .ACT_WIDTH(ACT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) mul_unit (
    .clk(clk),
    .rst(rst),
    .act(act),
    .w(w),
    .valid(valid),
    .precision(precision),

    .mantissa_out(mantissa_out),
    .start_acc(start_acc),
    .sign_out(sign_out),
    ._valid(_valid),
    ._act(_act),
    ._w(_w)
);

// ────────────── Accumulator Unit ──────────────
int_acc #(
    .ACC_WIDTH(ACC_WIDTH)
) acc_unit (
    .clk(clk),
    .rst(rst),
    .start(start_acc),                 // When new MAC result arrives
    .sign_in(sign_out),               // Final sign info
    .fixed_point_in(mantissa_out),    // Result of MAC unit
    .fixed_point_acc(fixed_point_acc),
    .fixed_point_out(fixed_point_out),
    .done(done)                       // 1-cycle done pulse
);

// ────────────── Detect end of systolic step ──────────────
reg done_tmp;
always @(posedge clk or negedge rst) begin
    if (!rst)
        done_tmp <= 0;
    else
        done_tmp <= done;
end

assign SA_done = !valid && (done && !done_tmp);

endmodule
