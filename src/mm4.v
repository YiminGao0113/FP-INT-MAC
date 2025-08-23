
module mm #(
    parameter ACT_WIDTH = 4,
    parameter ACC_WIDTH = 16,
    parameter N = 8,
    parameter K = 8,
    parameter ACT_FIFO_DEPTH = 8
)(
    input wire clk,
    input wire rst,
    input wire active,
    input wire [ACT_WIDTH-1:0] ain [N-1:0],
    input wire [ACT_WIDTH-1:0] bin [N-1:0],
    input wire wr_en_act,
    input wire wr_en_w,
    output wire done,
    output wire [ACC_WIDTH-1:0]    acc_out [N*N-1:0]
);

    wire [ACT_WIDTH-1:0] act_fifo_a_out [N-1:0];
    wire [ACT_WIDTH-1:0] act_fifo_b_out [N-1:0];
    wire [N-1:0] active_row;
    wire [N-1:0] active_column;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : row_fifos
            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(ACT_FIFO_DEPTH)) act_fifo_a_inst (
                .clk(clk),
                .rst(rst),
                .wr_en(wr_en_act),
                .rd_en(active_row[i]),
                .din(ain[i]),
                .dout(act_fifo_a_out[i]),
                .full(),
                .empty()
            );
            
            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(ACT_FIFO_DEPTH)) act_fifo_b_inst (
                .clk(clk),
                .rst(rst),
                .wr_en(wr_en_w),
                .rd_en(active_column[i]),
                .din(bin[i]),
                .dout(act_fifo_b_out[i]),
                .full(),
                .empty()
            );
        end
    endgenerate

    systolic_array #(
        .D_W(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) systolic_inst (
        .clk(clk),
        .rst(rst),
        .en(__active),
        .a_in(act_fifo_a_out),
        .b_in(act_fifo_b_out),
        .done(done),
        .acc_out(acc_out),
        .active_row(active_row),
        .active_column(active_column)
    );

    reg _active, __active;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            _active <= 0;
            __active <= 0;
        end 
        else begin
            _active <= active;
            __active <= _active;
        end
    end
    

endmodule
