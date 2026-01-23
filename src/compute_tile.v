// ============================================================
// compute_tile (Verilog)
// - Assumption: K_total % K_TILE == 0
// - Wraps mm and schedules multiple K_TILE passes to cover K_total
// - Accumulates partial sums into out_mem across passes
//
// Memory layout (matches your python):
//   act_mem[row*MAX_K + k] = A[row][k]
//   w_mem  [col*MAX_K + k] = W[col][k]   (column-major by col)
//   out_mem[row*N + col]   = C[row][col]
//
// IMPORTANT:
// - mm has internal accumulators + FIFOs; we pulse an internal reset
//   (mm_rst_n) for 1 cycle at start of each pass to clear them.
// - Output FIFO read latency is treated as 2 cycles here (PRIME=2).
//   This fixes the "column-shift" mismatch you saw.
// ============================================================

module compute_tile #(
    parameter integer ACT_WIDTH = 4,
    parameter integer ACC_WIDTH = 16,
    parameter integer N         = 8,

    parameter integer ACT_FIFO_DEPTH = 8,
    parameter integer OUT_FIFO_DEPTH = 32,

    parameter integer K_TILE = 8,
    parameter integer MAX_K  = 1024,

    parameter integer PIPE_LAT = 1
)(
    input  wire                         clk,
    input  wire                         rst,      // active-low reset style: !rst resets (like your mm)
    input  wire                         start,
    input  wire [$clog2(MAX_K+1)-1:0]   K_total,

    output reg                          busy,
    output reg                          done,     // 1-cycle pulse

    input  wire [ACT_WIDTH-1:0]         act_mem [0:N*MAX_K-1],
    input  wire [ACT_WIDTH-1:0]         w_mem   [0:N*MAX_K-1],
    output reg  [ACC_WIDTH-1:0]         out_mem [0:N*N-1]
);

    // ------------------------------------------------------------
    // Internal reset pulse to clear mm each pass
    // ------------------------------------------------------------
    reg  mm_clear_pulse;          // asserted 1 cycle
    wire mm_rst_n = rst & ~mm_clear_pulse; // mm resets when mm_rst_n==0

    // ------------------------------------------------------------
    // Signals to mm
    // ------------------------------------------------------------
    reg                    mm_active;
    reg                    mm_wr_en_act, mm_wr_en_w;
    reg  [ACT_WIDTH-1:0]   mm_ain [0:N-1];
    reg  [ACT_WIDTH-1:0]   mm_bin [0:N-1];

    wire                   mm_done;
    wire [ACC_WIDTH-1:0]   mm_acc_out [0:N*N-1]; // unused here, but kept
    reg  [N-1:0]           out_rd_en;
    wire [N-1:0]           out_empty;
    wire [N-1:0]           out_full;
    wire [ACC_WIDTH-1:0]   out_dout [0:N-1];

    // ------------------------------------------------------------
    // Instantiate mm
    // ------------------------------------------------------------
    mm #(
        .ACT_WIDTH      (ACT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .N              (N),
        .K              (K_TILE),
        .ACT_FIFO_DEPTH (ACT_FIFO_DEPTH),
        .OUT_FIFO_DEPTH (OUT_FIFO_DEPTH),
        .PIPE_LAT       (PIPE_LAT)
    ) u_mm (
        .clk        (clk),
        .rst        (mm_rst_n),
        .active     (mm_active),
        .ain        (mm_ain),
        .bin        (mm_bin),
        .wr_en_act  (mm_wr_en_act),
        .wr_en_w    (mm_wr_en_w),
        .done       (mm_done),
        .acc_out    (mm_acc_out),

        .out_rd_en  (out_rd_en),
        .out_empty  (out_empty),
        .out_full   (out_full),
        .out_dout   (out_dout)
    );

    // ------------------------------------------------------------
    // FSM encoding
    // ------------------------------------------------------------
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_CLEAR_OUT = 3'd1,
        S_CLEAR_MM  = 3'd2,
        S_LOAD      = 3'd3,
        S_RUN       = 3'd4,
        S_WAITDONE  = 3'd5,
        S_DRAIN     = 3'd6,
        S_NEXT      = 3'd7;

    reg [2:0] state;

    // ------------------------------------------------------------
    // Pass scheduling
    // ------------------------------------------------------------
    reg [$clog2(MAX_K+1)-1:0] k_base;      // base k for this pass
    reg [$clog2(MAX_K+1)-1:0] pass_cnt;    // 0..num_pass-1
    wire [$clog2(MAX_K+1)-1:0] num_pass = K_total / K_TILE;

    // step counter used in LOAD and RUN
    reg [$clog2(K_TILE+1)-1:0] step_cnt;

    // Drain counters
    localparam integer PRIME = 2; // <<< key fix: 2-cycle prime
    reg [$clog2(N+1)-1:0]  row_cnt;
    reg [$clog2(N+PRIME+2)-1:0] rd_cnt; // counts prime + N samples
    reg                        draining; // stays in a row once started

    integer rr;

    // ------------------------------------------------------------
    // Main sequential
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;

            mm_active      <= 1'b0;
            mm_wr_en_act   <= 1'b0;
            mm_wr_en_w     <= 1'b0;
            mm_clear_pulse <= 1'b0;

            out_rd_en      <= '0;

            k_base         <= '0;
            pass_cnt       <= '0;
            step_cnt       <= '0;

            row_cnt        <= '0;
            rd_cnt         <= '0;
            draining       <= 1'b0;

            for (rr = 0; rr < N*N; rr = rr + 1)
                out_mem[rr] <= {ACC_WIDTH{1'b0}};

            for (rr = 0; rr < N; rr = rr + 1) begin
                mm_ain[rr] <= {ACT_WIDTH{1'b0}};
                mm_bin[rr] <= {ACT_WIDTH{1'b0}};
            end
        end else begin
            // defaults every cycle
            done           <= 1'b0;
            mm_active      <= 1'b0;
            mm_wr_en_act   <= 1'b0;
            mm_wr_en_w     <= 1'b0;
            mm_clear_pulse <= 1'b0;
            out_rd_en      <= '0;

            case (state)

                // --------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        k_base   <= '0;
                        pass_cnt <= '0;
                        step_cnt <= '0;
                        state    <= S_CLEAR_OUT;
                    end
                end

                // --------------------------------------------
                // clear tile accumulation buffer once per run
                S_CLEAR_OUT: begin
                    for (rr = 0; rr < N*N; rr = rr + 1)
                        out_mem[rr] <= {ACC_WIDTH{1'b0}};
                    state <= S_CLEAR_MM;
                end

                // --------------------------------------------
                // clear mm (accumulators + FIFOs) once per pass
                // (1-cycle pulse to mm_rst_n=0)
                S_CLEAR_MM: begin
                    mm_clear_pulse <= 1'b1;
                    step_cnt <= '0;
                    row_cnt  <= '0;
                    rd_cnt   <= '0;
                    draining <= 1'b0;
                    state    <= S_LOAD;
                end

                // --------------------------------------------
                // push EXACTLY K_TILE beats into mm input FIFOs
                S_LOAD: begin
                    if (step_cnt < K_TILE) begin
                        for (rr = 0; rr < N; rr = rr + 1) begin
                            mm_ain[rr] <= act_mem[rr*MAX_K + (k_base + step_cnt)];
                            mm_bin[rr] <= w_mem  [rr*MAX_K + (k_base + step_cnt)];
                        end
                        mm_wr_en_act <= 1'b1;
                        mm_wr_en_w   <= 1'b1;
                        step_cnt     <= step_cnt + 1'b1;
                    end else begin
                        step_cnt <= '0;
                        state    <= S_RUN;
                    end
                end

                // --------------------------------------------
                // assert active for EXACTLY K_TILE cycles
                S_RUN: begin
                    if (step_cnt < K_TILE) begin
                        mm_active <= 1'b1;
                        step_cnt  <= step_cnt + 1'b1;
                    end else begin
                        step_cnt <= '0;
                        state    <= S_WAITDONE;
                    end
                end

                // --------------------------------------------
                S_WAITDONE: begin
                    if (mm_done) begin
                        row_cnt  <= '0;
                        rd_cnt   <= '0;
                        draining <= 1'b0;
                        state    <= S_DRAIN;
                    end
                end

                // --------------------------------------------
                // Drain each row FIFO:
                // - wait until !empty to START that row
                // - keep rd_en asserted for that row while draining
                // - PRIME cycles: rd_cnt = 0..PRIME-1 (no capture)
                // - capture N samples: rd_cnt = PRIME..PRIME+N-1
                //   col = rd_cnt - PRIME
                S_DRAIN: begin
                    // start draining this row only when it becomes non-empty
                    if (!draining) begin
                        if (!out_empty[row_cnt]) begin
                            draining <= 1'b1;
                            rd_cnt   <= '0;
                        end
                    end else begin
                        // keep read enable asserted while draining
                        out_rd_en[row_cnt] <= 1'b1;

                        if (rd_cnt < PRIME) begin
                            rd_cnt <= rd_cnt + 1'b1; // prime cycles
                        end else if (rd_cnt < (PRIME + N)) begin
                            // capture
                            out_mem[row_cnt*N + (rd_cnt - PRIME)] <=
                                out_mem[row_cnt*N + (rd_cnt - PRIME)] + out_dout[row_cnt];
                            rd_cnt <= rd_cnt + 1'b1;
                        end else begin
                            // finish this row
                            draining <= 1'b0;
                            rd_cnt   <= '0;

                            if (row_cnt == N-1) begin
                                row_cnt <= '0;
                                state   <= S_NEXT;
                            end else begin
                                row_cnt <= row_cnt + 1'b1;
                            end
                        end
                    end
                end

                // --------------------------------------------
                // next pass or finish
                S_NEXT: begin
                    if (pass_cnt == (num_pass - 1)) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        pass_cnt <= pass_cnt + 1'b1;
                        k_base   <= k_base + K_TILE;
                        state    <= S_CLEAR_MM;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule