module systolic_array #(
    parameter D_W        = 4,
    parameter ACC_WIDTH  = 16,
    parameter N          = 2
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    en,

    input  wire [D_W-1:0]          a_in [0:N-1],
    input  wire [D_W-1:0]          b_in [0:N-1],

    output wire [ACC_WIDTH-1:0]    c_out [0:N-1][0:N-1],
    output wire [ACC_WIDTH-1:0]    acc_out [N*N-1:0],

    output reg                     done,

    output wire [N-1:0]            active_row,
    output wire [N-1:0]            active_column,

    // NEW
    output wire [N-1:0]            row_done_pulse,
    output reg  [ACC_WIDTH-1:0]    acc_stream_out [N-1:0]
);

    // ------------------------------------------------------------
    // Internal systolic signals (UNCHANGED)
    // ------------------------------------------------------------
    wire [D_W-1:0] a_sig     [0:N][0:N-1];
    wire [D_W-1:0] a_sig_out [0:N][0:N-1];
    wire [D_W-1:0] b_sig     [0:N-1][0:N];
    wire [D_W-1:0] b_sig_out [0:N-1][0:N];
    wire           en_sig    [0:N][0:N-1];
    wire           en_sig_out[0:N][0:N-1];

    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : row
            for (c = 0; c < N; c = c + 1) begin : col
                mac #(
                    .D_W(D_W),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe (
                    .clk(clk),
                    .rst(rst),
                    .en(en_sig[r][c]),
                    .a(a_sig[r][c]),
                    .b(b_sig[r][c]),
                    .acc(c_out[r][c]),
                    .a_out(a_sig_out[r][c]),
                    .b_out(b_sig_out[r][c]),
                    .en_out(en_sig_out[r][c])
                );

                assign en_sig[r][c] =
                    (r==0 && c==0) ? en :
                    (c==0) ? en_sig_out[r-1][c] :
                             en_sig_out[r][c-1];

                assign a_sig[r][c] = (c == 0) ? a_in[r] : a_sig_out[r][c-1];
                assign b_sig[r][c] = (r == 0) ? b_in[c] : b_sig_out[r-1][c];
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // done (UNCHANGED)
    // ------------------------------------------------------------
    wire done_tmp;
    assign done_tmp = en_sig_out[N-1][N-1] & ~en_sig[N-1][N-1];

    always @(posedge clk or negedge rst)
        if (!rst) done <= 1'b0;
        else      done <= done_tmp;

    // ------------------------------------------------------------
    // activity signals (UNCHANGED)
    // ------------------------------------------------------------
    genvar rr, cc;
    generate
        for (rr = 0; rr < N; rr = rr + 1)
            assign active_row[rr] = en_sig[rr][0];

        for (cc = 0; cc < N; cc = cc + 1)
            assign active_column[cc] = en_sig[0][cc];
    endgenerate

    // ------------------------------------------------------------
    // flatten outputs (UNCHANGED)
    // ------------------------------------------------------------
    genvar fr, fc;
    generate
        for (fr = 0; fr < N; fr = fr + 1)
            for (fc = 0; fc < N; fc = fc + 1)
                assign acc_out[fr*N + fc] = c_out[fr][fc];
    endgenerate

    // ============================================================
    // NEW: row_done_pulse (same idea as FP-INT)
    // ============================================================
    wire [N-1:0] row_last_en;
    reg  [N-1:0] row_last_en_d;

    generate
        for (rr = 0; rr < N; rr = rr + 1)
            assign row_last_en[rr] = en_sig_out[rr][N-1];
    endgenerate

    always @(posedge clk or negedge rst)
        if (!rst) row_last_en_d <= '0;
        else      row_last_en_d <= row_last_en;

    generate
        for (rr = 0; rr < N; rr = rr + 1)
            assign row_done_pulse[rr] = row_last_en_d[rr] & ~row_last_en[rr];
    endgenerate

    // ============================================================
    // NEW: per-row stream-out engine (IDENTICAL to FP-INT)
    // ============================================================
    reg [N-1:0]            streaming;
    reg [$clog2(N)-1:0]    col_ptr [N-1:0];

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
                if (row_done_pulse[r_int]) begin
                    streaming[r_int] <= 1'b1;
                    col_ptr[r_int]   <= '0;
                end

                if (streaming[r_int]) begin
                    acc_stream_out[r_int] <= c_out[r_int][col_ptr[r_int]];

                    if (col_ptr[r_int] == N-1) begin
                        streaming[r_int] <= 1'b0;
                        col_ptr[r_int]   <= '0;
                    end else begin
                        col_ptr[r_int] <= col_ptr[r_int] + 1'b1;
                    end
                end else begin
                    acc_stream_out[r_int] <= '0;
                end
            end
        end
    end

endmodule