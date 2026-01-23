// ============================================================
// mm (Option 1 complete): per-row output FIFOs
//
// - systolic provides:
//     acc_stream_out[r] : the streamed accumulator value for row r
//     row_done_pulse[r] : 1-cycle pulse that STARTS the stream window
//   After row_done_pulse[r], systolic MUST present valid acc_stream_out[r]
//   for exactly N cycles (col0..colN-1), 1 value per cycle.
//
// - mm does:
//     N converters (one per row lane) -> fp16_row[r]
//     N per-row FIFOs (WIDTH=16)
//     write-enable is asserted for exactly N cycles after row_done_pulse[r]
//
// IMPORTANT limitation (same as before):
//   No backpressure into systolic. If out_full[r] goes high mid-stream,
//   remaining elements will be dropped. If you want lossless, we must
//   add ready/valid handshake back to systolic.
// ============================================================

module mm #(
    parameter ACT_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter N = 2,
    parameter K = 2,
    parameter ACT_FIFO_DEPTH = 32,
    parameter W_FIFO_DEPTH = 32,

    // per-row output fifo
    parameter OUT_FIFO_DEPTH = 64,
    parameter ACC_BINPT      = 10
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  active,
    input  wire [3:0]            precision,
    input  wire [4:0]            exp_set,
    input  wire [ACT_WIDTH-1:0]  act_din [N-1:0],
    input  wire                  w_din   [N-1:0],
    input  wire                  wr_en_act,
    input  wire                  wr_en_w,

    output wire                  done,
    output wire [4:0]            exp_out [N*N-1:0],
    output wire [ACC_WIDTH-1:0]  acc_out [N*N-1:0],

    // per-row fp16 output FIFOs (stream)
    input  wire [N-1:0]          out_rd_en,
    output wire [N-1:0]          out_empty,
    output wire [N-1:0]          out_full,
    output wire [15:0]           out_dout [N-1:0] // FP16 output rn
);

    // -------------------------
    // Input FIFOs (acts + weights)
    // -------------------------
    wire [ACT_WIDTH-1:0] act_fifo_out [N-1:0];
    wire                 w_fifo_out   [N-1:0];
    wire [N-1:0]         active_row;
    wire [N-1:0]         active_column;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : row_fifos
            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(ACT_FIFO_DEPTH)) act_fifo_inst (
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

            fifo #(.WIDTH(1), .DEPTH(W_FIFO_DEPTH)) w_fifo_inst (
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

    // -------------------------
    // Systolic outputs for streaming
    // -------------------------
    wire [ACC_WIDTH-1:0] acc_stream_out [N-1:0];
    wire [N-1:0]         row_done_pulse;

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
        .acc_stream_out(acc_stream_out),
        .active_row(active_row),
        .active_column(active_column),
        .row_done_pulse(row_done_pulse)
    );

    // ------------------------------------------------------------
    // Per-row FP16 conversion (N converters)
    // ------------------------------------------------------------
    wire [15:0] fp16_row [N-1:0];

    genvar r;
    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_ROW_CONV
            acc_exp_to_fp16 #(
                .ACC_W(ACC_WIDTH),
                .ACC_BINPT(ACC_BINPT)
            ) cvt (
                .acc   (acc_stream_out[r]),
                .exp_in(exp_set),
                .fp16  (fp16_row[r])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Write window control: after row_done_pulse[r], write N cycles
    // ------------------------------------------------------------
    reg [N-1:0]            streaming;
    reg [$clog2(N):0]      cnt [N-1:0];  // counts 0..N-1

    integer rr;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            streaming <= '0;
            for (rr = 0; rr < N; rr = rr + 1) begin
                cnt[rr] <= '0;
            end
        end else begin
            for (rr = 0; rr < N; rr = rr + 1) begin
                // start stream window on done pulse, only if FIFO not full
                if (row_done_pulse[rr] && !out_full[rr]) begin
                    streaming[rr] <= 1'b1;
                    cnt[rr]       <= '0;
                end

                // advance window
                if (streaming[rr]) begin
                    if (cnt[rr] == (N-1)) begin
                        streaming[rr] <= 1'b0;
                        cnt[rr]       <= '0;
                    end else begin
                        cnt[rr] <= cnt[rr] + 1'b1;
                    end
                end
            end
        end
    end

    // write enable is high during the stream window
    reg [N-1:0] out_wr_en;
    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_ROW_WR
            always @(posedge clk) out_wr_en[r] <= streaming[r] & ~out_full[r];
        end
    endgenerate

    // ------------------------------------------------------------
    // Per-row output FIFOs (N FIFOs)
    // ------------------------------------------------------------
    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_OUT_FIFOS
            fifo #(
                .WIDTH(16),
                .DEPTH(OUT_FIFO_DEPTH)
            ) out_fifo (
                .clk  (clk),
                .rst  (rst),
                .wr_en(out_wr_en[r]),
                .rd_en(out_rd_en[r]),
                .din  (fp16_row[r]),
                .dout (out_dout[r]),
                .full (out_full[r]),
                .empty(out_empty[r])
            );
        end
    endgenerate

endmodule