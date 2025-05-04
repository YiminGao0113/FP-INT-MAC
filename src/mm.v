
module mm #(
    parameter ACT_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter N = 2,
    parameter K = 2,
    parameter FIFO_DEPTH = 16
)(
    input wire clk,
    input wire rst,
    input wire active,
    input wire [3:0] precision,
    input wire [4:0] exp_set,
    input wire [ACT_WIDTH-1:0] act_din [N-1:0],
    input wire w_din [N-1:0],
    input wire wr_en_act,
    input wire wr_en_w,
    output wire done,
    output wire [4:0] exp_out [N*N-1:0],
    output wire [ACC_WIDTH-1:0] acc_out [N*N-1:0]
);

    wire [ACT_WIDTH-1:0] act_fifo_out [N-1:0];
    wire w_fifo_out [N-1:0];
    wire [N-1:0] active_row;
    wire [N-1:0] active_column;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : row_fifos
            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(FIFO_DEPTH)) act_fifo_inst (
                .clk(clk),
                .rst(rst),
                .precision(precision),
                .wr_en(wr_en_act),
                .rd_en(active_row[i]),
                .din(act_din[i]),
                .dout(act_fifo_out[i]),
                .full(),
                .empty()
            );

            fifo #(.WIDTH(1), .DEPTH(FIFO_DEPTH)) w_fifo_inst (
                .clk(clk),
                .rst(rst),
                .wr_en(wr_en_w),
                .rd_en(active_column[i]),
                .din(w_din[i]),
                .dout(w_fifo_out[i]),
                .full(),
                .empty()
            );
        end
    endgenerate

    systolic #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) systolic_inst (
        .clk(clk),
        .rst(rst),
        .active(active),
        .precision(precision),
        .act_in(act_fifo_out),
        .w_in(w_fifo_out),
        .exp_set(exp_set),
        .done(done),
        .exp_out(exp_out),
        .acc_out(acc_out),
        .active_row(active_row),
        .active_column(active_column)
    );

endmodule
