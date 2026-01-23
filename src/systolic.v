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
    input                   w_in   [N-1:0],
    input [4:0]             exp_set,
    output                  done,
    output [4:0]            exp_out [N*N-1:0],
    output [ACC_WIDTH-1:0]  acc_out [N*N-1:0],

    // stream out one element per row per cycle for N cycles after row_done_pulse
    output reg [ACC_WIDTH-1:0]  acc_stream_out [N-1:0],

    output [N-1:0]          active_row,
    output [N-1:0]          active_column,

    output [N-1:0]          row_done_pulse
);

    // -------------------------
    // Internal signals
    // -------------------------
    wire [ACT_WIDTH-1:0] pe_act   [0:N][0:N];
    wire                 pe_w     [0:N][0:N];
    wire                 pe_valid [0:N][0:N];
    wire [N*N-1:0]       pe_done;

    wire fifo_wr_en [(N-1)*N-1:0];
    wire fifo_rd_en [(N-1)*N-1:0];
    wire fifo_active[(N-1)*N-1:0];

    reg active_reg;
    always @(posedge clk or negedge rst) begin
        if (!rst) active_reg <= 1'b0;
        else      active_reg <= active;
    end

    // -------------------------
    // PE mesh (unchanged)
    // -------------------------
    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                wire local_valid;
                reg  local_valid_reg;
                reg  fifo_empty_reg;
                wire fifo_empty;
                wire _w_input;
                wire [ACC_WIDTH-1:0] fixed_point_out_temp;

                assign local_valid = (i == 0 && j == 0) ? active_reg :
                                     (j == 0 && i > 0) ? fifo_active[(i-1)*N + j] :
                                                        pe_valid[i][j-1];

                always @(posedge clk or negedge rst) begin
                    if (!rst) begin
                        fifo_empty_reg  <= 1'b1;
                        local_valid_reg <= 1'b0;
                    end else begin
                        fifo_empty_reg  <= fifo_empty;
                        local_valid_reg <= local_valid;
                    end
                end

                fp_int_mac #(
                    .ACT_WIDTH(ACT_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid((j==0)?local_valid_reg: (local_valid & local_valid_reg)),
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

                if (i < N - 1) begin : VERT_FIFO
                    fifo #(
                        .WIDTH(1),
                        .DEPTH(16)
                    ) fifo_inst (
                        .clk(clk),
                        .rst(rst),
                        .wr_en(fifo_wr_en[i*N + j]),
                        .rd_en(fifo_rd_en[i*N + j]),
                        .din(pe_w[i][j]),
                        .dout(pe_w[i+1][j]),
                        .full(),
                        .empty(fifo_empty)
                    );

                    assign fifo_wr_en[i*N + j] = local_valid_reg;
                    assign fifo_rd_en[i*N + j] = !fifo_empty_reg;
                    assign fifo_active[i*N + j] = (!fifo_empty_reg) & (!fifo_empty);
                end
            end
        end
    endgenerate

    // -------------------------
    // activity signals (unchanged)
    // -------------------------
    genvar rr, cc;
    generate
        for (rr = 0; rr < N; rr = rr + 1) begin : gen_active_row
            assign active_row[rr] = (rr == 0) ? active_reg : fifo_active[(rr - 1) * N];
        end
        for (cc = 0; cc < N; cc = cc + 1) begin : gen_active_column
            assign active_column[cc] = (cc == 0) ? active_reg : pe_valid[0][cc - 1];
        end
    endgenerate

    // boundary inputs
    generate
        for (i = 0; i < N; i = i + 1) begin : input_row
            assign pe_act[i][0] = act_in[i];
        end
        for (j = 0; j < N; j = j + 1) begin : input_col
            assign pe_w[0][j] = w_in[j];
        end
    endgenerate

    assign done = pe_done[N*N-1];

    // -------------------------
    // row_done_pulse (unchanged)
    // -------------------------
    wire [N-1:0] row_last_valid;
    reg  [N-1:0] row_last_valid_d;

    generate
        for (rr = 0; rr < N; rr = rr + 1) begin : GEN_ROW_LAST_VALID
            assign row_last_valid[rr] = pe_valid[rr][N-1];
        end
    endgenerate

    always @(posedge clk or negedge rst) begin
        if (!rst) row_last_valid_d <= '0;
        else      row_last_valid_d <= row_last_valid;
    end

    generate
        for (rr = 0; rr < N; rr = rr + 1) begin : GEN_ROW_DONE_PULSE
            assign row_done_pulse[rr] = row_last_valid_d[rr] & ~row_last_valid[rr];
        end
    endgenerate

    // =========================================================
    // NEW: stream-out engine using ONLY row_done_pulse
    // Each row streams N beats (col 0..N-1) after row_done_pulse.
    // =========================================================
    reg [N-1:0] streaming;
    reg [$clog2(N)-1:0] col_ptr [N-1:0];

    integer r_int;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            streaming <= '0;
            for (r_int = 0; r_int < N; r_int = r_int + 1) begin
                col_ptr[r_int] <= '0;
                acc_stream_out[r_int] <= '0;
            end
        end else begin
            for (r_int = 0; r_int < N; r_int = r_int + 1) begin
                // start streaming window
                if (row_done_pulse[r_int]) begin
                    streaming[r_int] <= 1'b1;
                    col_ptr[r_int]   <= '0;
                end

                if (streaming[r_int]) begin
                    acc_stream_out[r_int] <= acc_out[r_int*N + col_ptr[r_int]];

                    if (col_ptr[r_int] == N-1) begin
                        streaming[r_int] <= 1'b0;
                        col_ptr[r_int]   <= '0;
                    end else begin
                        col_ptr[r_int] <= col_ptr[r_int] + 1'b1;
                    end
                end else begin
                    // not streaming: drive 0 (don't-care)
                    acc_stream_out[r_int] <= '0;
                end
            end
        end
    end

endmodule