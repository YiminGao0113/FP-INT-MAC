
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
    output                  done,
    output [4:0]            exp_out [N*N-1:0],
    output [ACC_WIDTH-1:0]  acc_out [N*N-1:0],
    output [N-1:0]          active_row,
    output [N-1:0]          active_column
);

    // Internal signals
    wire [ACT_WIDTH-1:0] pe_act [0:N][0:N];
    wire                 pe_w   [0:N][0:N];
    wire                 pe_valid [0:N][0:N];
    wire [N*N-1:0]       pe_done;
    wire [4:0]           pe_exp_out [N*N-1:0];
    wire [ACC_WIDTH-1:0] pe_acc_out [N*N-1:0];
    // reg  [ACC_WIDTH-1:0] pe_acc_reg [N*N-1:0];

    // FIFO connections between vertically adjacent PEs (for weight and valid)
    wire fifo_din [(N-1)*N-1:0];
    wire fifo_dout [(N-1)*N-1:0];
    wire fifo_wr_en [(N-1)*N-1:0];
    wire fifo_rd_en [(N-1)*N-1:0];
    wire fifo_active [(N-1)*N-1:0];
    reg active_reg;
    
    always @(posedge clk or negedge rst) begin
        if (!rst) active_reg <= 0;
        else active_reg <= active;
    end


    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                wire local_valid, local_valid_for_pe;
                reg local_valid_reg;
                reg fifo_empty_reg;
                wire fifo_empty;
                wire _w_input;
                wire [ACC_WIDTH-1:0] fixed_point_out_temp;
                // assign local_valid = (i == 0 && j == 0) ? active_reg :
                //                      (j == 0 && i > 0) ? fifo_active[(i-1)*N + j] : pe_valid[i][j-1];
                assign local_valid = (i == 0 && j == 0) ? active_reg :
                                     (j == 0 && i > 0) ? fifo_active[(i-1)*N + j] : pe_valid[i][j-1];

                // assign local_valid_for_pe =  (i == 0 && j == 0) ? active_reg :
                //                      (j == 0 && i > 0) ? fifo_active[(i-1)*N + j] : previous_pe_generated_valid;
                // reg local_valid_reg;
                // wire previous_pe_generated_valid;
                // assign _w_input = (i < N - 1) ? fifo_din[i*N + j] : 1'b0;

                // assign active_row[i] = (i == 0)? active : fifo_active[(i-1)*N];
                // assign active_column[j] = (i == 0)? active : pe_valid[0][j-1]
                // assign active_column[j] = (i == 0)? local_valid : active_row[i];

                always @(posedge clk) begin
                    fifo_empty_reg <= fifo_empty;
                    local_valid_reg <= local_valid;
                    // previous_pe_generated_valid_reg <= pe_valid[i][j-1];
                end
                // assign previous_pe_generated_valid = previous_pe_generated_valid_reg & pe_valid[i][j-1];

                fp_int_mac #(
                    .ACT_WIDTH(ACT_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid((j==0)?local_valid_reg: local_valid&local_valid_reg),
                    .precision(precision),
                    .act(pe_act[i][j]),
                    .w(pe_w[i][j]),
                    ._act(pe_act[i][j+1]),
                    ._w(_w_input),
                    ._valid(pe_valid[i][j]),
                    .exp_set(exp_set),
                    .fixed_point_acc(fixed_point_out_temp),
                    .exp_out(exp_out[i*N+j]),
                    .fixed_point_out(fixed_point_out_temp),
                    .SA_done(pe_done[i*N+j])
                );

                assign acc_out[i*N + j] = fixed_point_out_temp;
                if (i < N - 1) begin
                    fifo  #(
                        .WIDTH(1),
                        .DEPTH(16)
                    )fifo_inst(
                        .clk(clk),
                        .rst(rst),
                        .wr_en(fifo_wr_en[i*N + j]),
                        .rd_en(fifo_rd_en[i*N + j]),
                        .din(pe_w[i][j]),
                        // .precision(precision),
                        .dout(pe_w[i+1][j]),
                        .full(),
                        .empty(fifo_empty)
                        // ,
                        // .active(fifo_active[i*N + j])
                    );

                    assign fifo_wr_en[i*N + j] = local_valid_reg;
                    assign fifo_rd_en[i*N + j] = !fifo_empty_reg;
                    assign fifo_active[i*N + j] = (!fifo_empty_reg)&(!fifo_empty);
                end
            end
        end
    endgenerate

    genvar rr, cc;
    generate
        for (rr = 0; rr < N; rr = rr + 1) begin : gen_active_row
            assign active_row[rr] = (rr == 0) ? active_reg : fifo_active[(rr - 1) * N];
        end
        for (cc = 0; cc < N; cc = cc + 1) begin : gen_active_column
            assign active_column[cc] = (cc == 0) ? active_reg : pe_valid[0][cc - 1];
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
    // generate
    //     for (i = 0; i <= N; i = i + 1) begin
    //         assign pe_act[i][N] = '0;
    //     end
    //     for (j = 0; j <= N; j = j + 1) begin
    //         assign pe_w[N][j] = '0;
    //     end
    // endgenerate

    // Control logic
    // reg done_tmp;

    // always @(posedge clk or negedge rst) begin
    //     if (!rst) begin
    //         done   <= 0;
    //         done_tmp <= 0;
    //     end else begin
    //         done_tmp <= pe_valid[N-1][N-1];
    //         done <= !pe_valid[N-1][N-1] && done_tmp;
    //     end
    // end
    assign done = pe_done[N*N-1];

endmodule