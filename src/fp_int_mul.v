// To get started fp_int_mul unit here is only for fixed-precision arithmetic: fp16 x+ int4 operations
// fp16 : 1=bit sign + 5-bit exponent + 10-bit mantissa
module fp_int_mul #(
    parameter ACT_WIDTH = 16,
    parameter W_WIDTH  = 4,
    parameter ACC_WIDTH = 32
)(
    input                  clk,
    input                  rst,
    input [ACT_WIDTH-1:0]  activation,
    input [W_WIDTH-1:0]    weight,
    input                  start,
    output reg             busy,
    // output [ACC_WIDTH-1:0] result,
    output                 sign_out,
    output [4:0]           exp_out,
    output [13:0]          mantissa_out,
    output                 done    
);

reg [W_WIDTH-1:0]          weight_reg;
reg [ACT_WIDTH-1:0]        activation_reg;
wire                       act_sign;
wire [4:0]                 act_exponent;
wire [9:0]                act_mantissa;
wire [10:0]               fixed_mantissa;
assign {act_sign, act_exponent, act_mantissa} = activation_reg;
assign fixed_mantissa = {1'b1, act_mantissa};
assign sign_out = weight_reg[W_WIDTH-1] ^ activation_reg[ACT_WIDTH-1];
assign exp_out  = activation[15:10];

// Weight line and activation initialization
always @(posedge clk or negedge rst)
    if (!rst) begin
        weight_reg      <= 0;
        activation_reg  <= 0;
        busy            <= 0;
    end
    else if (start&&!busy) begin
        weight_reg      <= weight;
        activation_reg  <= activation;
        busy            <= 1;
    end

reg [2:0] count;
// counter logic here
always @(posedge clk or negedge rst)
    if (!rst || start&&!busy) begin
        count <= 0;
    end
    else if (busy && count != 4) count <= count + 1;
    else if (busy && count == 4) begin
        busy  <= 0;
    end

assign done = count == 4;

// The accumulator in the Multiplier unit
reg  [13:0] mantissa_reg;
// wire  [14:0] mantissa_temp;
reg   [13:0] shifted_fp;

fixed_point_adder fixed_adder(mantissa_reg, shifted_fp, mantissa_out);


always @(posedge clk or negedge rst)
    if (!rst) mantissa_reg <= 0;
    else mantissa_reg <= mantissa_out;

always @(*) begin
    case (count)
        2'b00: shifted_fp <= 14'b0;
        2'b01: shifted_fp <= weight_reg[2]? fixed_mantissa<<2: 14'b0;
        2'b10: shifted_fp <= weight_reg[1]? fixed_mantissa<<1: 14'b0;
        2'b11: shifted_fp <= weight_reg[0]? fixed_mantissa: 14'b0;
        default: shifted_fp <= 14'b0;
    endcase
end

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