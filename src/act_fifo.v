module act_fifo #(
    parameter WIDTH = 1,
    parameter DEPTH = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire wr_en,
    input  wire rd_en,
    input [3:0] precision,
    input  wire [WIDTH-1:0] din,
    output reg  [WIDTH-1:0] dout,
    // input [3:0] precision,
    output wire full,
    output wire empty
    // output wire active
);

    reg [WIDTH-1:0] mem [0:DEPTH-1] ;
    reg [$clog2(DEPTH)-1:0]  wr_ptr;
    reg [$clog2(DEPTH)-1:0]  rd_ptr;
    reg [$clog2(DEPTH):0]  count;
    
    reg [3:0] precision_count;
    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            dout   <= 0;
            // active <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= 0;
        end else begin
            // if (count == precision) active <= 1;
            // else if (empty)         active <= 0;
            // Simultaneous read and write
            // if (wr_en && !full && rd_en && !empty) begin
            //     mem[wr_ptr] <= din;
            //     wr_ptr <= wr_ptr + 1;
            //     dout   <= mem[rd_ptr];
            //     rd_ptr <= rd_ptr + 1;
            //     // count stays the same
            // end
            // Write only
            // else 
            if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + 1;
                count  <= count + 1;
            end
            // Read only
            else if (rd_en && !empty && precision_count==0) begin
                dout <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                count  <= count - 1;
            end
        end
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) precision_count <= 0;
        else if (rd_en) begin
            precision_count <= (precision_count < precision-1)? precision_count + 1 : 0;
        end

    end

endmodule
