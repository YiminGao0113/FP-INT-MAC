module int4_bitserial_mul #(
parameter ACT_WIDTH = 4,
    parameter ACC_WIDTH = 8
)(
    input                       clk,
    input                       rst,
    input signed [ACT_WIDTH-1:0] act,
    input                       w,            // 1-bit weight (bit-serial, LSB to MSB)
    input                       valid,
    input [2:0]                 precision,    // Usually 4 for INT4

    output reg signed [ACC_WIDTH-1:0] mantissa_out,  // Final MAC output
    output reg                        start_acc,     // Pulse: computation done
    output                           _valid,         // Aligned valid signal
    output reg [ACT_WIDTH-1:0]       _act,
    output reg                       _w,
    output reg                       sign_out        // Final sign (w XOR a)
);

reg [ACT_WIDTH-1:0]       act_temp, __act;
reg                       sign_w;
reg [2:0]                 count;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        count     <= 0;
        act_temp  <= 0;
        __act     <= 0;
        _act      <= 0;
        _w        <= 0;
    end else begin
        _act <= __act;

        if (valid) begin
            act_temp <= act;
            _w <= w;

            if (count < precision - 1) begin
                count <= count + 1;
                __act <= __act;
            end else begin
                count <= 0;
                __act <= act_temp;
            end
        end else begin
            count <= 0;
        end
    end
end

// ───── Valid signal pipeline alignment ─────
parameter MAX_PRECISION = 8;
reg [MAX_PRECISION:0] shift_reg;

always @(posedge clk or negedge rst) begin
    if (!rst)
        shift_reg <= 0;
    else
        shift_reg <= {shift_reg[MAX_PRECISION-1:0], valid};
end

assign _valid = shift_reg[precision] || shift_reg[precision-1];

// ───── Accumulation logic ─────
reg signed [ACC_WIDTH-1:0] shifted_act;
reg signed [ACC_WIDTH-1:0] accumulator;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        shifted_act <= 0;
        accumulator <= 0;
    end else if (valid) begin
        if (count == 0) begin
            shifted_act <= {{(ACC_WIDTH - ACT_WIDTH - 1){act[ACT_WIDTH-1]}}, act, 1'b0};
        end else begin
            shifted_act <= shifted_act <<< 1;
        end

        // if (w) begin
        if (count == precision - 1)
            accumulator <= w ? accumulator - shifted_act : accumulator;
        else if (count == 0)
            accumulator <= w ? act : 0;
        else
            accumulator <= w ? accumulator + shifted_act : accumulator;
        // end
    end
end

// ───── Final output and control ─────
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        mantissa_out <= 0;
        start_acc <= 0;
        sign_out <= 0;
    end else begin
        if (count == 0) begin
            sign_w <= w;
            sign_out <= act[ACT_WIDTH-1] ^ w;
            start_acc <= 0;
        end else if (count == precision - 1) begin
            mantissa_out <= accumulator;
            start_acc <= 1;
        end else begin
            start_acc <= 0;
        end
    end
end

endmodule