module systolic_array #(
    parameter D_W        = 4,
    parameter ACC_WIDTH  = 16,
    parameter N          = 2   // array dimension (NxN)
    // parameter PROP_DELAY = 1    // forward delay cycles
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    en,
    input  wire [D_W-1:0]          a_in [0:N-1],     // row inputs
    input  wire [D_W-1:0]          b_in [0:N-1],     // column inputs
    output wire [ACC_WIDTH-1:0]    c_out [0:N-1][0:N-1] // outputs
);

    // Internal systolic signals
    wire [D_W-1:0] a_sig     [0:N][0:N-1];   // (N+1)xN
    wire [D_W-1:0] a_sig_out     [0:N][0:N-1];   // (N+1)xN
    wire [D_W-1:0] b_sig     [0:N-1][0:N];   // N x (N+1)
    wire [D_W-1:0] b_sig_out     [0:N-1][0:N];   // N x (N+1)
    wire           en_sig    [0:N][0:N-1];   // (N+1)xN
    wire           en_sig_out[0:N][0:N-1];   // (N+1)xN
    wire en01, en_out00;
    assign en10 = en_sig[1][0];
    assign en_out00 = en_sig_out[0][0];

    // --- Instantiate PE grid ---
    genvar r, c;
    generate
        for (r=0; r<N; r=r+1) begin : row
            for (c=0; c<N; c=c+1) begin : col
                mac #(
                    .D_W(D_W),
                    .ACC_WIDTH(ACC_WIDTH)
                    // .PROP_DELAY(PROP_DELAY)
                ) pe (
                    .clk(clk),
                    .rst(rst),
                    .en(en_sig[r][c]),
                    .a(a_sig[r][c]),
                    .b(b_sig[r][c]),
                    .acc(c_out[r][c]),   // directly map to outputs
                    .a_out(a_sig_out[r][c]),
                    .b_out(b_sig_out[r][c]),
                    .en_out(en_sig_out[r][c])
                );
                assign en_sig[r][c] = (r==0&c==0)? en : ((c==0)? en_sig_out[r-1][c]:en_sig_out[r][c-1]);
                assign a_sig[r][c] = (c == 0)? a_in[r] : a_sig_out[r][c-1];
                assign b_sig[r][c] = (r == 0)? b_in[c] : b_sig_out[r-1][c];
            end
        end
    endgenerate

endmodule
