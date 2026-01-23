module mac_comp #
(
    parameter D_W       = 4,
    parameter ACC_WIDTH = 16
)
(
    input  wire                  clk,
    input  wire                  rst,   // active-low, synchronous (matches your style)
    input  wire                  en,
    input  wire [D_W-1:0]        a,
    input  wire [D_W-1:0]        b,
    output reg  [ACC_WIDTH-1:0]  acc
);

    wire [2*D_W-1:0] prod;
    assign prod = a * b;

    reg  en_d;
    wire en_rise = en & ~en_d;

    always @(posedge clk) begin
        if (!rst) begin
            acc  <= {ACC_WIDTH{1'b0}};
            en_d <= 1'b0;
        end else begin
            en_d <= en;

            // First cycle of a "pass": reset + take first product
            if (en_rise) begin
                acc <= {{(ACC_WIDTH-2*D_W){1'b0}}, prod};
            end
            // Remaining enabled cycles: accumulate
            else if (en) begin
                acc <= acc + {{(ACC_WIDTH-2*D_W){1'b0}}, prod};
            end
        end
    end

endmodule

// Wrapper PE with systolic forwarding and configurable delay
module mac #
(
    parameter D_W            = 4,
    parameter ACC_WIDTH      = 16
    // parameter PROP_DELAY     = 1   // cycles to hold before propagating
)
(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  en,
    input  wire [D_W-1:0]        a,
    input  wire [D_W-1:0]        b,
    output wire [ACC_WIDTH-1:0]  acc,

    // systolic pass-through (delayed by PROP_DELAY cycles)
    output wire [D_W-1:0]        a_out,
    output wire [D_W-1:0]        b_out,
    output wire                  en_out
);

    // --- Core MAC computation ---
    mac_comp #(
        .D_W(D_W),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_mac4 (
        .clk(clk),
        .rst(rst),
        .en(en_reg),
        .a(a),
        .b(b),
        .acc(acc)
    );

    // --- Shift registers for delayed propagation ---
    reg [D_W-1:0] a_reg;
    reg [D_W-1:0] b_reg;
    reg           en_reg;

    integer i;
    always @(posedge clk) begin
        if (!rst) begin
            a_reg <= 0;
            b_reg <= 0;
            en_reg <= 0;
        end else begin
            a_reg  <= a;
            b_reg <= b;
            en_reg <= en;
        end
    end

    // Outputs after PROP_DELAY cycles
    assign a_out  = a_reg;
    assign b_out  = b_reg;
    assign en_out = en_reg;

endmodule
