module int_acc #(
    parameter ACC_WIDTH = 32
)(
    input                     clk,
    input                     rst,
    input                     start,
    input  [ACC_WIDTH-1:0]    fixed_point_acc,
    input  signed [7:0]      fixed_point_in,
    output [ACC_WIDTH-1:0]    fixed_point_out,
    output reg                done
);

reg [ACC_WIDTH-1:0] fixed_point_reg;

// Sign-extend fixed_point_in to ACC_WIDTH
wire signed [ACC_WIDTH-1:0] fixed_point_in_ext = fixed_point_in;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        fixed_point_reg <= 0;
        done <= 0;
    end
    else if (start && !done) begin
        fixed_point_reg <= fixed_point_acc + fixed_point_in_ext;
        done <= 1;
    end
    else begin
        done <= 0;
    end
end

assign fixed_point_out = fixed_point_reg;

endmodule
