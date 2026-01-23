module compute_tile #(
    parameter ACT_WIDTH = 4,
    parameter ACC_WIDTH = 16,
    parameter N = 8,
    parameter MAX_K = 256
)(
    input  wire clk,
    input  wire rst,

    // -------- control (AXI-lite side) --------
    input  wire        start,
    input  wire [15:0] K,          // runtime K
    input  wire [2:0]  precision,
    output reg         done,

    // -------- memories (abstract for now) --------
    input  wire [ACT_WIDTH-1:0] act_mem [0:N*MAX_K-1],
    input  wire [ACT_WIDTH-1:0] w_mem   [0:N*MAX_K-1],
    output reg  [ACC_WIDTH-1:0] out_mem [0:N*N-1]
);

    // ------------------------------------------------
    // FSM
    // ------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        COMPUTE,
        DRAIN,
        DONE
    } state_t;

    state_t state, next_state;

    // ------------------------------------------------
    // mm interface signals
    // ------------------------------------------------
    reg active_mm;
    reg wr_en_act, wr_en_w;

    reg [ACT_WIDTH-1:0] act_din [N-1:0];
    reg [ACT_WIDTH-1:0] w_din   [N-1:0];

    wire mm_done;
    wire [ACC_WIDTH-1:0] acc_out [N*N-1:0];

    // ------------------------------------------------
    // Counters
    // ------------------------------------------------
    reg [$clog2(MAX_K)-1:0] k_cnt;

    // ------------------------------------------------
    // mm instance (YOUR EXISTING CODE)
    // ------------------------------------------------
    mm #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N)
    ) mm_inst (
        .clk(clk),
        .rst(rst),
        .active(active_mm),
        .precision(precision),
        .act_din(act_din),
        .w_din(w_din),
        .wr_en_act(wr_en_act),
        .wr_en_w(wr_en_w),
        .done(mm_done),
        .acc_out(acc_out)
    );

    // ------------------------------------------------
    // FSM sequential
    // ------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ------------------------------------------------
    // FSM combinational
    // ------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    if (start) next_state = LOAD;
            LOAD:    if (k_cnt == K) next_state = COMPUTE;
            COMPUTE: if (mm_done) next_state = DRAIN;
            DRAIN:   next_state = DONE;
            DONE:    next_state = IDLE;
        endcase
    end

    // ------------------------------------------------
    // Control logic
    // ------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            k_cnt     <= 0;
            wr_en_act <= 0;
            wr_en_w   <= 0;
            active_mm <= 0;
            done      <= 0;
        end else begin
            done <= 0;

            case (state)
                IDLE: begin
                    k_cnt <= 0;
                end

                LOAD: begin
                    wr_en_act <= 1;
                    wr_en_w   <= 1;
                    for (i = 0; i < N; i = i + 1) begin
                        act_din[i] <= act_mem[i*K + k_cnt];
                        w_din[i]   <= w_mem  [i*K + k_cnt];
                    end
                    k_cnt <= k_cnt + 1;
                end

                COMPUTE: begin
                    wr_en_act <= 0;
                    wr_en_w   <= 0;
                    active_mm <= 1;
                end

                DRAIN: begin
                    active_mm <= 0;
                    for (i = 0; i < N*N; i = i + 1)
                        out_mem[i] <= acc_out[i];
                end

                DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule