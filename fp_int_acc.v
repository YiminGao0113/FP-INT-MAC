module fp_int_acc (
    input          clk,
    input          rst,
    input          start,
    input          sign_in,
    input  [4:0]   exp_min,
    input  [31:0]  fixed_point_acc,
    input  [4:0]   exp_in,
    input  [13:0]  fixed_point_in,
    output [4:0]   exp_out,
    output [31:0]  fixed_point_out
);

wire [4:0] diff;
assign diff = exp_in - exp_min;

reg [31:0] fixed_point_reg;
reg [4:0] exp_reg;

always @(posedge clk or negedge rst)
    if (!rst) begin
        fixed_point_reg <= 0;
        exp_reg <= 0;
    end
    else if (start) begin
        if (~&diff) begin
            exp_reg <= exp_min;
            fixed_point_reg <= sign_in? fixed_point_acc - fixed_point_in: fixed_point_acc + fixed_point_in;
        end
        else if (!diff[4]) begin
            exp_reg <= exp_min;
            fixed_point_reg <= sign_in? fixed_point_acc - (fixed_point_in>>(~diff + 1)): fixed_point_acc + (fixed_point_in>>(~diff + 1));
        end
        else begin
            exp_reg <= exp_in;
            fixed_point_reg <= sign_in? (fixed_point_acc>>diff) - fixed_point_in: (fixed_point_acc>>diff) + fixed_point_in;
        end
    end

assign fixed_point_out = fixed_point_reg;
assign exp_out = exp_reg;

endmodule