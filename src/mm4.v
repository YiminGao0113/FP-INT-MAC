module mm #(
    parameter ACT_WIDTH = 4,
    parameter ACC_WIDTH = 16,
    parameter N = 8,
    parameter K = 8,
    parameter ACT_FIFO_DEPTH = 8,
    parameter OUT_FIFO_DEPTH = 32,
    parameter PIPE_LAT = 1   // latency from row_done_pulse -> first valid acc_stream_out
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         active,

    // signed inputs into mm
    input  wire signed [ACT_WIDTH-1:0]  ain [N-1:0],
    input  wire signed [ACT_WIDTH-1:0]  bin [N-1:0],

    input  wire                         wr_en_act,
    input  wire                         wr_en_w,

    output wire                         done,
    output wire signed [ACC_WIDTH-1:0]  acc_out [N*N-1:0],

    // per-row output FIFO
    input  wire [N-1:0]                 out_rd_en,
    output wire [N-1:0]                 out_empty,
    output wire [N-1:0]                 out_full,

    // signed outputs from output FIFOs
    output wire signed [ACC_WIDTH-1:0]  out_dout [N-1:0]
);

    // ============================================================
    // Input FIFOs (store unsigned bits, then cast to signed)
    // ============================================================
    wire [ACT_WIDTH-1:0] act_fifo_a_u [N-1:0];
    wire [ACT_WIDTH-1:0] act_fifo_b_u [N-1:0];

    wire signed [ACT_WIDTH-1:0] act_fifo_a_out [N-1:0];
    wire signed [ACT_WIDTH-1:0] act_fifo_b_out [N-1:0];

    // active_row/active_column drive FIFO reads
    wire [N-1:0] active_row;
    wire [N-1:0] active_column;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : IN_FIFOS
            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(ACT_FIFO_DEPTH)) fifo_a (
                .clk   (clk),
                .rst   (rst),
                .wr_en (wr_en_act),
                .rd_en (active_row[i]),
                // cast signed -> raw bits into FIFO
                .din   (ain[i][ACT_WIDTH-1:0]),
                .dout  (act_fifo_a_u[i]),
                .full  (),
                .empty ()
            );

            act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(ACT_FIFO_DEPTH)) fifo_b (
                .clk   (clk),
                .rst   (rst),
                .wr_en (wr_en_w),
                .rd_en (active_column[i]),
                .din   (bin[i][ACT_WIDTH-1:0]),
                .dout  (act_fifo_b_u[i]),
                .full  (),
                .empty ()
            );

            // signed "view" of FIFO outputs
            assign act_fifo_a_out[i] = $signed(act_fifo_a_u[i]);
            assign act_fifo_b_out[i] = $signed(act_fifo_b_u[i]);
        end
    endgenerate

    // ============================================================
    // Active pipeline (same as before)
    // ============================================================
    reg _active, __active;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            _active  <= 1'b0;
            __active <= 1'b0;
        end else begin
            _active  <= active;
            __active <= _active;
        end
    end

    // ============================================================
    // Systolic array (must accept signed a_in/b_in internally)
    // ============================================================
    wire signed [ACC_WIDTH-1:0] acc_stream_out [N-1:0];
    wire [N-1:0]                row_done_pulse;

    systolic_array #(
        .D_W(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) systolic_inst (
        .clk            (clk),
        .rst            (rst),
        .en             (__active),

        // IMPORTANT: these are signed now
        .a_in            (act_fifo_a_out),
        .b_in            (act_fifo_b_out),

        .done           (done),

        // ideally make these signed too in systolic_array, but if not,
        // you can keep them unsigned and cast at the very end.
        .acc_out         (acc_out),

        .acc_stream_out  (acc_stream_out),
        .row_done_pulse  (row_done_pulse),

        .active_row      (active_row),
        .active_column   (active_column)
    );

    // ============================================================
    // Stream control (same logic)
    // ============================================================
    reg [N-1:0] streaming;
    reg [N-1:0] stream_valid;
    reg [$clog2(N):0]            cnt [N-1:0];
    reg [$clog2(PIPE_LAT+1):0]   lat_cnt [N-1:0];

    integer r;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            streaming    <= '0;
            stream_valid <= '0;
            for (r = 0; r < N; r = r + 1) begin
                cnt[r]     <= '0;
                lat_cnt[r] <= '0;
            end
        end else begin
            for (r = 0; r < N; r = r + 1) begin
                // start stream
                if (row_done_pulse[r]) begin
                    streaming[r]    <= 1'b1;
                    stream_valid[r] <= 1'b0;
                    cnt[r]          <= '0;
                    lat_cnt[r]      <= '0;
                end

                // wait for pipeline latency
                if (streaming[r] && !stream_valid[r]) begin
                    if (PIPE_LAT == 0) begin
                        stream_valid[r] <= 1'b1;
                    end else if (lat_cnt[r] == PIPE_LAT-1) begin
                        stream_valid[r] <= 1'b1;
                    end else begin
                        lat_cnt[r] <= lat_cnt[r] + 1'b1;
                    end
                end

                // stream data for N cycles
                if (stream_valid[r]) begin
                    if (cnt[r] == N-1) begin
                        streaming[r]    <= 1'b0;
                        stream_valid[r] <= 1'b0;
                        cnt[r]          <= '0;
                    end else begin
                        cnt[r] <= cnt[r] + 1'b1;
                    end
                end
            end
        end
    end

    // ============================================================
    // Output FIFOs: store raw bits, cast to signed at output
    // ============================================================
    wire [N-1:0] out_wr_en;
    generate
        for (i = 0; i < N; i = i + 1) begin : OUT_WR
            assign out_wr_en[i] = stream_valid[i] & ~out_full[i];
        end
    endgenerate

    wire [ACC_WIDTH-1:0] out_dout_u [N-1:0];

    generate
        for (i = 0; i < N; i = i + 1) begin : OUT_FIFOS
            act_fifo #(
                .WIDTH(ACC_WIDTH),
                .DEPTH(OUT_FIFO_DEPTH)
            ) out_fifo (
                .clk   (clk),
                .rst   (rst),
                .wr_en (out_wr_en[i]),
                .rd_en (out_rd_en[i]),

                // signed -> raw bits into FIFO
                .din   (acc_stream_out[i][ACC_WIDTH-1:0]),
                .dout  (out_dout_u[i]),

                .full  (out_full[i]),
                .empty (out_empty[i])
            );

            // signed view for external users
            assign out_dout[i] = $signed(out_dout_u[i]);
        end
    endgenerate

endmodule