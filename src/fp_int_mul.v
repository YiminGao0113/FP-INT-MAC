  // To get started fp_int_mul unit here is only for fixed-precision arithmetic: fp16 x+ int4 operations
// fp16 : 1=bit sign + 5-bit exponent + 10-bit mantissa
module fp_int_mul #(
    parameter ACT_WIDTH = 16,
    // parameter W_WIDTH  = 4,
    parameter ACC_WIDTH = 32
)(
    input                       clk,
    input                       rst,
    input [ACT_WIDTH-1:0]       act,
    input                       w,
    input                       valid,
    input [3:0]                 precision,
    output reg                  sign_out,
    output [4:0]                exp_out,
    output [13:0]               mantissa_out,
    output reg                  start_acc,
    output                      _valid,
    output reg [ACT_WIDTH-1:0]  _act,
    output reg                  _w
);

reg [ACT_WIDTH-1:0]       act_temp, __act;
reg                       w_sign;
wire                      act_sign;
wire [4:0]                act_exponent;
wire [9:0]                act_mantissa;
wire [10:0]               fixed_mantissa;
assign {act_sign, act_exponent, act_mantissa} = act_temp;
assign fixed_mantissa = {1'b1, act_mantissa};
assign exp_out = act_exponent;

reg [2:0]             count;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        count <= 0;
        // start_acc <= 0;
        act_temp <= 0;
        _w <= 0;
        __act <= 0;
        _act <= 0;
    end
    else begin
        _act <= __act;
        if (valid) begin
            act_temp <= act;
            _w <= w;
            if (count<precision-1) begin
                count <= count + 1;
                __act <= __act;
            end
            else begin
                count <= 0;
                __act <= act_temp;
            end
        end
        else begin
            count <= 0;
            __act <= __act;
        end
    end
end


// reg [3:0] shift_reg;

// always @(posedge clk or negedge rst) begin
//     if (!rst)
//         shift_reg <= 4'b0;
//     else
//         shift_reg <= {shift_reg[2:0], valid};
// end

// assign _valid = shift_reg[3];

parameter MAX_PRECISION = 8;  // maximum supported precision
reg [MAX_PRECISION:0] shift_reg;

always @(posedge clk or negedge rst) begin
    if (!rst)
        shift_reg <= 0;
    else
        shift_reg <= {shift_reg[MAX_PRECISION-1:0], valid};
end

assign _valid = shift_reg[precision] || shift_reg[precision-1];


// The accumulator in the Multiplier unit
reg  [13:0] mantissa_reg;
// wire  [14:0] mantissa_temp;
reg   [13:0] shifted_fp;

fixed_point_adder fixed_adder(mantissa_reg, shifted_fp, mantissa_out);

always @(posedge clk or negedge rst)
    if (!rst) mantissa_reg <= 0;
    else if (!start_acc&valid) mantissa_reg <= mantissa_out;
    else mantissa_reg<=0;


always @(*) begin
    case (count)
        3'b000: begin
            shifted_fp = 14'b0;
            // start_acc = 0;
        end
        3'b001: shifted_fp = sign_out? (w? 14'b0:fixed_mantissa<<2) : (w? fixed_mantissa<<2: 14'b0); // negative : positive
        3'b010: shifted_fp = sign_out? (w? 14'b0:fixed_mantissa<<1) : (w? fixed_mantissa<<1: 14'b0); // negative : positive
        3'b011: begin
            shifted_fp = sign_out? (w? fixed_mantissa: fixed_mantissa<<1): (w? fixed_mantissa: 14'b0); // negative integer: if LSB = 0 >> fixed_mantissa<<1, if LSB = 1 >> fixed_mantissa
            // start_acc = 1;
        end
        default: begin
            shifted_fp = 14'b0;
            // sign_out = 0;
            // start_acc = 0;
        end
    endcase
end

always @(posedge clk or negedge rst)
    if (!rst) begin
        start_acc <= 0;
        sign_out <= 0;
        // exp_out <= 0;
    end
    else if (count == 0) begin
        // exp_out <= act_exponent;
        sign_out <= w^act[ACT_WIDTH-1];
        start_acc <= 0;
    end
    // else if (count == 1) begin
    //     sign_out <= w^act[ACT_WIDTH-1];
    // end
    else if (count==precision-1) start_acc <= 1;
    else start_acc <= 0;

endmodule

module fixed_point_adder(
    input      [13:0]  A,
    input      [13:0]  B,
    output     [13:0]  C
);
// This is the intermediate represetation in order to have the least # of rounding at the end of computation.
// The 14-bit fixed point representation consists of 4 bits . 10 bits mantissa
// which is able to hold everything accurately without 
assign C = A + B;
endmodule