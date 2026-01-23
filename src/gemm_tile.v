`timescale 1ns/1ps

module gemm_tile #(
    parameter integer ACT_WIDTH = 4,
    parameter integer ACC_WIDTH = 16,

    parameter integer N_FULL    = 8,
    parameter integer TILE_N    = 4,

    parameter integer MAX_K     = 1024,
    parameter integer K_TILE    = 4,
    parameter integer ACT_FIFO_DEPTH = 8,
    parameter integer OUT_FIFO_DEPTH = 32,
    parameter integer PIPE_LAT  = 1
)(
    input  wire                         clk,
    input  wire                         rst,

    input  wire                         start,
    input  wire [$clog2(MAX_K+1)-1:0]   K_total,

    output reg                          busy,
    output reg                          done,

    input  wire [ACT_WIDTH-1:0]         act_mem_full [0:N_FULL*MAX_K-1],
    input  wire [ACT_WIDTH-1:0]         w_mem_full   [0:N_FULL*MAX_K-1],
    output reg  [ACC_WIDTH-1:0]         out_mem_full [0:N_FULL*N_FULL-1]
);

    localparam integer NUM_TILES = N_FULL / TILE_N;

    // Tile-local memories for compute_tile
    reg  [ACT_WIDTH-1:0] act_tile_mem [0:TILE_N*MAX_K-1];
    reg  [ACT_WIDTH-1:0] w_tile_mem   [0:TILE_N*MAX_K-1];
    wire [ACC_WIDTH-1:0] out_tile_mem [0:TILE_N*TILE_N-1];

    reg  tile_start;
    wire tile_busy;
    wire tile_done;

    compute_tile #(
        .ACT_WIDTH      (ACT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .N              (TILE_N),
        .ACT_FIFO_DEPTH (ACT_FIFO_DEPTH),
        .OUT_FIFO_DEPTH (OUT_FIFO_DEPTH),
        .K_TILE         (K_TILE),
        .MAX_K          (MAX_K),
        .PIPE_LAT       (PIPE_LAT)
    ) u_tile (
        .clk     (clk),
        .rst     (rst),
        .start   (tile_start),
        .K_total (K_total),
        .busy    (tile_busy),
        .done    (tile_done),
        .act_mem (act_tile_mem),
        .w_mem   (w_tile_mem),
        .out_mem (out_tile_mem)
    );

    // FSM
    localparam [2:0]
        S_IDLE       = 3'd0,
        S_CLEAR_C    = 3'd1,
        S_LOAD_TILE  = 3'd2,
        S_KICK_TILE  = 3'd3,   // NEW
        S_WAIT_TILE  = 3'd4,   // NEW
        S_STORE_TILE = 3'd5,
        S_NEXT_TILE  = 3'd6,
        S_DONE       = 3'd7;

    reg [2:0] state;

    // tile indices
    reg [$clog2(NUM_TILES)-1:0] tr;
    reg [$clog2(NUM_TILES)-1:0] tc;

    // base row/col for this tile
    wire [$clog2(N_FULL)-1:0] base_row = tr * TILE_N;
    wire [$clog2(N_FULL)-1:0] base_col = tc * TILE_N;

    // load/store counters (1 element per cycle)
    reg [$clog2(TILE_N*MAX_K+1)-1:0]     load_idx;
    reg [$clog2(TILE_N*TILE_N+1)-1:0]    store_idx;

    // decode load indices
    wire [$clog2(TILE_N)-1:0] load_r = load_idx / MAX_K;
    wire [$clog2(MAX_K)-1:0]  load_k = load_idx % MAX_K;

    // decode store indices
    wire [$clog2(TILE_N)-1:0] store_r = store_idx / TILE_N;
    wire [$clog2(TILE_N)-1:0] store_c = store_idx % TILE_N;

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;

            tr         <= '0;
            tc         <= '0;

            load_idx   <= '0;
            store_idx  <= '0;

            tile_start <= 1'b0;

            for (i = 0; i < N_FULL*N_FULL; i = i + 1)
                out_mem_full[i] <= '0;

            for (i = 0; i < TILE_N*MAX_K; i = i + 1) begin
                act_tile_mem[i] <= '0;
                w_tile_mem[i]   <= '0;
            end
        end else begin
            done       <= 1'b0;
            tile_start <= 1'b0;   // default: no start pulse

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        tr   <= '0;
                        tc   <= '0;
                        state <= S_CLEAR_C;
                    end
                end

                S_CLEAR_C: begin
                    for (i = 0; i < N_FULL*N_FULL; i = i + 1)
                        out_mem_full[i] <= '0;
                    load_idx <= '0;
                    state    <= S_LOAD_TILE;
                end

                // Load A rows + B cols for this tile
                S_LOAD_TILE: begin
                    if (load_idx < TILE_N*MAX_K) begin
                        act_tile_mem[load_idx] <= act_mem_full[(base_row + load_r)*MAX_K + load_k];
                        w_tile_mem[load_idx]   <= w_mem_full  [(base_col + load_r)*MAX_K + load_k];
                        load_idx <= load_idx + 1'b1;
                    end else begin
                        load_idx <= '0;
                        state    <= S_KICK_TILE;
                    end
                end

                // Pulse compute_tile start ONCE
                S_KICK_TILE: begin
                    tile_start <= 1'b1;    // 1-cycle pulse
                    state      <= S_WAIT_TILE;
                end

                // Wait for compute_tile completion
                S_WAIT_TILE: begin
                    if (tile_done) begin
                        store_idx <= '0;
                        state     <= S_STORE_TILE;
                    end
                end

                // Store tile outputs into full C
                S_STORE_TILE: begin
                    if (store_idx < TILE_N*TILE_N) begin
                        out_mem_full[(base_row + store_r)*N_FULL + (base_col + store_c)]
                            <= out_tile_mem[store_idx];
                        store_idx <= store_idx + 1'b1;
                    end else begin
                        store_idx <= '0;
                        state     <= S_NEXT_TILE;
                    end
                end

                // next (tr, tc)
                S_NEXT_TILE: begin
                    if (tc == NUM_TILES-1) begin
                        tc <= '0;
                        if (tr == NUM_TILES-1) begin
                            state <= S_DONE;
                        end else begin
                            tr <= tr + 1'b1;
                            state <= S_LOAD_TILE;
                        end
                    end else begin
                        tc <= tc + 1'b1;
                        state <= S_LOAD_TILE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule