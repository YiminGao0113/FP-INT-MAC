module systolic #(
    parameter ACT_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter N         = 2 // N x N systolic array
)(
    input                   clk,
    input                   rst,
    input                   start,
    input [3:0]             precision,
    input                   K, // The length of the input arrays - (NxK) x (KxN) GEMM
    input [N-1:0]           weight,
    input [ACT_WIDTH-1:0]   act [N-1:0],
    output                  done,
    input [4:0]             exp_set,
    output [4:0]            exp_out,
    output [ACC_WIDTH-1:0]  acc_out[[N*N-1:0]]
);

endmodule