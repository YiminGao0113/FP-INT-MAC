module fifo (
    input  wire clk,
    input  wire rst,
    input  wire wr_en,
    input  wire rd_en,
    input  wire din,
    output reg  dout,
    input [3:0] precision,
    output wire full,
    output wire empty
    // output wire active
);

    reg [15:0] mem;
    reg [3:0]  wr_ptr;
    reg [3:0]  rd_ptr;
    reg [4:0]  count;

    assign full  = (count == 16);
    assign empty = (count == 0);

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            dout   <= 0;
            // active <= 0;
            for (i = 0; i < 16; i = i + 1)
                mem[i] <= 0;
        end else begin
            // if (count == precision) active <= 1;
            // else if (empty)         active <= 0;
            // Simultaneous read and write
            if (wr_en && !full && rd_en && !empty) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + 1;
                dout   <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                // count stays the same
            end
            // Write only
            else if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + 1;
                count  <= count + 1;
            end
            // Read only
            else if (rd_en && !empty) begin
                dout <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                count  <= count - 1;
            end
        end
    end

endmodule
