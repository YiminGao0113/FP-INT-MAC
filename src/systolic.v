module systolic #(
    parameter ACT_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter N         = 2
)(
    input                   clk,
    input                   rst,
    input                   active,
    input [3:0]             precision,
    input [ACT_WIDTH-1:0]   act_in [N-1:0],
    input                  w_in [N-1:0],
    input [4:0]             exp_set,
    output reg              done,
    output [4:0]            exp_out [N*N-1:0],
    output [ACC_WIDTH-1:0]  acc_out [N*N-1:0]
);

    // Internal signals
    wire [ACT_WIDTH-1:0] pe_act [0:N][0:N];
    wire                 pe_w   [0:N][0:N];
    wire                 pe_valid [0:N][0:N];
    wire [N*N-1:0]       pe_done;
    wire [4:0]           pe_exp_out [N*N-1:0];
    wire [ACC_WIDTH-1:0] pe_acc_out [N*N-1:0];
    reg  [ACC_WIDTH-1:0] pe_acc_reg [N*N-1:0];

    // FIFO connections between vertically adjacent PEs (for weight and valid)
    wire fifo_din [(N-1)*N-1:0];
    wire fifo_dout [(N-1)*N-1:0];
    wire fifo_wr_en [(N-1)*N-1:0];
    wire fifo_rd_en [(N-1)*N-1:0];
    wire fifo_active [(N-1)*N-1:0];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                wire local_valid;
                wire _w_input;
                assign local_valid = (i == 0 && j == 0) ? active :
                                     (j == 0 && i > 0) ? fifo_active[(i-1)*N + j] : pe_valid[i][j-1];
                assign _w_input = (i < N - 1) ? fifo_din[i*N + j] : 1'b0;

                fp_int_mac #(
                    .ACT_WIDTH(ACT_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid(local_valid),
                    .precision(precision),
                    .act(pe_act[i][j]),
                    .w(pe_w[i][j]),
                    ._act(pe_act[i][j+1]),
                    ._w(_w_input),
                    ._valid(pe_valid[i][j]),
                    .exp_set(exp_set),
                    .fixed_point_acc(pe_acc_reg[i*N+j]),
                    .exp_out(pe_exp_out[i*N+j]),
                    .fixed_point_out(pe_acc_out[i*N+j]),
                    .done(pe_done[i*N+j])
                );

                if (i < N - 1) begin
                    fifo fifo_inst (
                        .clk(clk),
                        .rst(rst),
                        .wr_en(fifo_wr_en[i*N + j]),
                        .rd_en(fifo_rd_en[i*N + j]),
                        .din(fifo_din[i*N + j]),
                        .precision(precision),
                        .dout(pe_w[i+1][j]),
                        .full(),
                        .empty(),
                        .active(fifo_active[i*N + j])
                    );

                    assign fifo_wr_en[i*N + j] = pe_valid[i][j];
                    assign fifo_rd_en[i*N + j] = 1'b1;
                end
            end
        end
    endgenerate

    // Connect the boundary inputs
    generate
        for (i = 0; i < N; i = i + 1) begin : input_row
            assign pe_act[i][0] = act_in[i];
        end
        for (j = 0; j < N; j = j + 1) begin : input_col
            assign pe_w[0][j] = w_in[j];
        end
    endgenerate

    // Unused boundary outputs
    generate
        for (i = 0; i <= N; i = i + 1) begin
            assign pe_act[i][N] = '0;
        end
        for (j = 0; j <= N; j = j + 1) begin
            assign pe_w[N][j] = '0;
        end
    endgenerate

    // Control logic
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            done   <= 0;
        end else begin
            if (active) begin
                if (!pe_valid[N-1][N-1]) begin
                    done <= 1;
                end else begin
                    done <= 0;
                end
            end else begin
                done <= 0;
            end
        end
    end

    // Accumulator register update
    always @(posedge clk) begin
        if (active) begin
            for (integer idx = 0; idx < N*N; idx = idx + 1) begin
                pe_acc_reg[idx] <= pe_acc_out[idx];
            end
        end
    end

    // Output assignments
    genvar k;
    generate
        for (k = 0; k < N*N; k = k + 1) begin : output_assign
            assign exp_out[k] = pe_exp_out[k];
            assign acc_out[k] = pe_acc_out[k];
        end
    endgenerate

endmodule