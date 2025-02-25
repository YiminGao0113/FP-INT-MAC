  // To get started fp_int_mul unit here is only for fixed-precision arithmetic: fp16 x+ int4 operations
// fp16 : 1=bit sign + 5-bit exponent + 10-bit mantissa
module fp_int_mul #(
    parameter ACT_WIDTH = 16,
    // parameter W_WIDTH  = 4,
    parameter ACC_WIDTH = 32
)(
    input                  clk,
    input                  rst,
    input [ACT_WIDTH-1:0]  act,
    input                  w,
    input                  valid,
    input                  set, 
    input [3:0]            precision,
    // output [ACC_WIDTH-1:0] result,
    output reg             sign_out,
    output reg [4:0]       exp_out,
    output [13:0]          mantissa_out,
    output reg             start_acc    
);

// reg [ACT_WIDTH-1:0]       _act;
// reg                       _w;
wire                      act_sign;
wire [4:0]                act_exponent;
wire [9:0]                act_mantissa;
wire [10:0]               fixed_mantissa;
assign {act_sign, act_exponent, act_mantissa} = act;
assign fixed_mantissa = {1'b1, act_mantissa};

reg [3:0]             _precision;

always @(posedge clk or negedge rst)
    if (!rst) _precision <= 0;
    else if (set) _precision <= precision;

reg [2:0]             count;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        count <= 0;
        // start_acc <= 0;
        // _act <= 0;
        // _w <= 0;
    end
    else begin
        if (valid) begin
            // _act <= act;
            // _w <= w;
            if (count<_precision-1) count <= count + 1;
            else begin
                count <= 0;
                // start_acc <= 1;
            end
        end
        else begin
            // _act <= _act;
            count <= 0;
        end
    end
end

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
        3'b001: shifted_fp = w? fixed_mantissa<<2: 14'b0;
        3'b010: shifted_fp = w? fixed_mantissa<<1: 14'b0;
        3'b011: begin
            shifted_fp = w? fixed_mantissa: 14'b0;
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
        exp_out <= 0;
    end
    else if (count == 0) begin
        exp_out <= act_exponent;
        sign_out <= w^act[ACT_WIDTH-1];
        start_acc <= 0;
    end
    else if (count==_precision-1) start_acc <= 1;
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