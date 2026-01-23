// ============================================================
// acc_exp_to_fp16.v  (Verilog-2001 friendly; works with iverilog)
// Converts (signed fixed-point accumulator + 5-bit biased exponent)
// into IEEE-754 FP16 {sign, exp[4:0], frac[9:0]}.
//
// IMPORTANT:
//   - exp_in is assumed to be FP16-style biased exponent (bias=15).
//   - acc is assumed to have ACC_BINPT fractional bits (binary point).
//   - Underflow is flushed to 0 (no subnormals).
//   - Overflow saturates to +/−Inf.
//   - Rounding is simple "guard-bit" rounding (good enough to start).
// ============================================================
module acc_exp_to_fp16 #(
    parameter integer ACC_W      = 32,
    parameter integer ACC_BINPT  = 10,  // <<< set this to match your accumulator Q-format
    parameter integer EXP_BIAS   = 15
)(
    input  wire signed [ACC_W-1:0] acc,
    input  wire [4:0]              exp_in,   // biased exponent (FP16 field style)
    output wire [15:0]             fp16
);

    // --------------------------------------------------------
    // Sign + magnitude
    // --------------------------------------------------------
    wire sign = acc[ACC_W-1];
    wire [ACC_W-1:0] mag = sign ? (~acc + {{(ACC_W-1){1'b0}},1'b1}) : acc[ACC_W-1:0];
    wire is_zero = (mag == {ACC_W{1'b0}});

    // --------------------------------------------------------
    // Leading-one detect for magnitude
    // msb_idx = index of highest '1' in mag
    // --------------------------------------------------------
    integer k;
    reg [$clog2(ACC_W)-1:0] msb_idx;
    always @(*) begin
        msb_idx = {($clog2(ACC_W)){1'b0}};
        for (k = ACC_W-1; k >= 0; k = k - 1) begin
            if (mag[k]) begin
                msb_idx = k[$clog2(ACC_W)-1:0];
                k = -1; // break loop
            end
        end
    end

    // --------------------------------------------------------
    // Exponent math
    //
    // value = mag * 2^(-ACC_BINPT) * 2^(exp_in - EXP_BIAS)
    // mag ~= 1.xxx * 2^(msb_idx)
    // => unbiased_exp = (exp_in - EXP_BIAS) + (msb_idx - ACC_BINPT)
    // => biased_exp   = unbiased_exp + EXP_BIAS
    //
    // NOTE: exp_in is 5-bit, but treat as integer.
    // --------------------------------------------------------
    integer unbiased_exp;
    integer biased_exp;
    always @(*) begin
        unbiased_exp = ( (exp_in * 1) - EXP_BIAS ) + (msb_idx * 1) - ACC_BINPT;
        biased_exp   = unbiased_exp + EXP_BIAS;
    end

    // --------------------------------------------------------
    // Normalize mantissa
    // We want:
    //   hidden 1 at position 11
    //   mantissa bits in [10:1] (10 bits)
    //   guard bit at [0] for rounding
    // --------------------------------------------------------
    reg [ACC_W+12:0] norm;
    integer sh;
    always @(*) begin
        norm = { (ACC_W+13){1'b0} };
        if (!is_zero) begin
            if (msb_idx <= 11) begin
                sh   = 11 - msb_idx;
                norm = {{13{1'b0}}, mag} << sh;
            end else begin
                sh   = msb_idx - 11;
                norm = {{13{1'b0}}, mag} >> sh;
            end
        end
    end

    wire [9:0] mant_pre = norm[10:1]; // 10 fraction bits
    wire       guard    = norm[0];

    // simple rounding using guard bit
    wire [10:0] mant_rounded_ext = {1'b0, mant_pre} + guard; // can overflow into bit10

    // --------------------------------------------------------
    // Assemble FP16 (flush subnormals to 0)
    // --------------------------------------------------------
    reg [4:0] exp_field;
    reg [9:0] frac_field;
    reg [5:0] exp_tmp; // for increment with overflow check

    always @(*) begin
        if (is_zero) begin
            exp_field  = 5'd0;
            frac_field = 10'd0;
        end
        else if (biased_exp <= 0) begin
            // underflow -> 0 (no subnormals)
            exp_field  = 5'd0;
            frac_field = 10'd0;
        end
        else if (biased_exp >= 31) begin
            // overflow -> inf
            exp_field  = 5'h1F;
            frac_field = 10'd0;
        end
        else begin
            if (mant_rounded_ext[10]) begin
                // mantissa overflow due to rounding -> exponent + 1, frac = 0
                exp_tmp = biased_exp + 1;
                if (exp_tmp >= 31) begin
                    exp_field  = 5'h1F;
                    frac_field = 10'd0;
                end else begin
                    exp_field  = exp_tmp[4:0];
                    frac_field = 10'd0;
                end
            end else begin
                exp_field  = biased_exp[4:0];
                frac_field = mant_rounded_ext[9:0];
            end
        end
    end

    assign fp16 = {sign, exp_field, frac_field};

endmodule