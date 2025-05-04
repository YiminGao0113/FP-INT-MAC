`timescale 1ns/1ps

module mm_tb;

    parameter ACT_WIDTH = 16;
    parameter ACC_WIDTH = 32;
    parameter N = 2;
    parameter K = 2;
    parameter FIFO_DEPTH = 16;

    reg clk, rst, active;
    reg [3:0] precision;
    reg [4:0] exp_set;

    wire done;
    wire [4:0] exp_out [N*N-1:0];
    wire [ACC_WIDTH-1:0] acc_out [N*N-1:0];

    reg [ACT_WIDTH-1:0] act_mem [0:N*K-1];
    reg w_mem [0:N*K*4-1]; // Extra room for serialized weight bits

    reg [ACT_WIDTH-1:0] act_din [N-1:0];
    reg w_din [N-1:0];

    reg wr_en_act;
    reg wr_en_w;

    // Expected outputs for each PE
    reg [ACC_WIDTH-1:0] expected_out [0:N*N-1];

    initial begin
        expected_out[0] = 32'hFFFFD800;
        expected_out[1] = 32'hFFFFF400;
        expected_out[2] = 32'hFFFFD800;
        expected_out[3] = 32'hFFFFF000;
    end

    always #5 clk = ~clk;

    // Instantiate mm wrapper
    mm #(
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .N(N),
        .K(K),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .active(active),
        .precision(precision),
        .exp_set(exp_set),
        .act_din(act_din),
        .w_din(w_din),
        .wr_en_act(wr_en_act),
        .wr_en_w(wr_en_w),
        .done(done),
        .exp_out(exp_out),
        .acc_out(acc_out)
    );

    integer k, r, p, l;
    initial begin
        $dumpfile("build/mm_tb.vcd");
        $dumpvars(0, mm_tb);

        clk = 0;
        rst = 1;
        active = 0;
        precision = 4;
        exp_set = 5'd15;

        $readmemh("tb/act.mem", act_mem);
        $readmemh("tb/w.mem", w_mem);

        #10 rst = 0;
        #10 rst = 1;

        wr_en_act = 1;
        for (k = 0; k < K; k = k + 1) begin
            for (r = 0; r < N; r = r + 1) begin
                act_din[r] = act_mem[r*K + k];
            end
            #10;
        end
        wr_en_act = 0;
        #10;

        wr_en_w = 1;
        for (k = 0; k < K; k = k + 1) begin
            for (p = 0; p < precision; p = p + 1) begin
                for (r = 0; r < N; r = r + 1) begin
                    w_din[r] = w_mem[(r*K + k)*precision + p];
                end
                #10;
            end
        end
        wr_en_w = 0;
        #20;

        for (k = 0; k < K*precision; k = k + 1) begin
            active = 1;
            #10;
        end
        active = 0;

        #200;
        $display("Systolic completed:");
        for (r = 0; r < N*N; r = r + 1) begin
            $display("acc_out[%0d] = %h", r, acc_out[r]);
        end

        $finish;
    end

    always @(posedge done) begin
        $display("==== [DONE asserted] Checking Outputs ====");
        for (l = 0; l < N*N; l= l + 1) begin
            if (acc_out[l] !== expected_out[l])
                $display("Mismatch at PE[%0d][%0d]: got %h, expected %h", l/N, l%N, acc_out[l], expected_out[l]);
            else
                $display("PE[%0d][%0d] correct: %h", l/N, l%N, acc_out[l]);
        end
        $display("==========================================");
    end

endmodule

// `timescale 1ns/1ps

// module mm_tb;

//     parameter ACT_WIDTH = 16;
//     parameter ACC_WIDTH = 32;
//     parameter N = 2;
//     parameter K = 2;
//     parameter FIFO_DEPTH = 16;

//     reg clk, rst, active;
//     reg [3:0] precision;
//     reg [4:0] exp_set;

//     wire [ACT_WIDTH-1:0] act_in [N-1:0];
//     wire w_in [N-1:0];

//     wire done;
//     wire [4:0] exp_out [N*N-1:0];
//     wire [ACC_WIDTH-1:0] acc_out [N*N-1:0];
//     wire [N-1:0] active_row;
//     wire [N-1:0] active_column;

//     reg [ACT_WIDTH-1:0] act_mem [0:N*K-1];
//     reg w_mem [0:N*K*4-1]; // Extra room for serialized weight bits

//     reg [ACT_WIDTH-1:0] act_din [N-1:0];
//     reg w_din [N-1:0];

//     reg wr_en_act;
//     reg wr_en_w;

//     wire [ACT_WIDTH-1:0] act_fifo_out [N-1:0];
//     wire w_fifo_out [N-1:0];
//     wire act_fifo_empty [N-1:0];
//     wire w_fifo_empty [N-1:0];
    
//     // Expected outputs for each PE
//     reg [ACC_WIDTH-1:0] expected_out [0:N*N-1];
    
//     initial begin
//         expected_out[0] = 32'hFFFFD800;  // PE[0][0]
//         expected_out[1] = 32'hFFFFF400;  // PE[0][1]
//         expected_out[2] = 32'hFFFFD800;  // PE[1][0]    
//         expected_out[3] = 32'hFFFFF000;  // PE[1][1]
//     end


//     // Clock
//     always #5 clk = ~clk;

//     // Instantiate FIFOs and connect to DUT
//     genvar i;
//     generate
//         for (i = 0; i < N; i = i + 1) begin: row_fifos
//             act_fifo #(.WIDTH(ACT_WIDTH), .DEPTH(FIFO_DEPTH)) act_fifo_inst (
//                 .clk(clk),
//                 .rst(rst),
//                 .precision(precision),
//                 .wr_en(wr_en_act),
//                 .rd_en(active_row[i]),
//                 .din(act_din[i]),
//                 .dout(act_fifo_out[i]),
//                 .full(),
//                 .empty(act_fifo_empty[i])
//             );
//             assign act_in[i] = act_fifo_out[i];
//         end
//     endgenerate

//     genvar q;
//     generate
//         for (q = 0; q < N; q = q + 1) begin: col_fifos
//             fifo #(.WIDTH(1), .DEPTH(FIFO_DEPTH)) w_fifo_inst (
//                 .clk(clk),
//                 .rst(rst),
//                 .wr_en(wr_en_w),
//                 .rd_en(active_column[q]),
//                 .din(w_din[q]),
//                 .dout(w_fifo_out[q]),
//                 .full(),
//                 .empty(w_fifo_empty[q])
//             );
//             assign w_in[q] = w_fifo_out[q];
//         end
//     endgenerate

//     // Instantiate systolic array
//     systolic #(
//         .ACT_WIDTH(ACT_WIDTH),
//         .ACC_WIDTH(ACC_WIDTH),
//         .N(N)
//     ) dut (
//         .clk(clk),
//         .rst(rst),
//         .active(active),
//         .precision(precision),
//         .act_in(act_in),
//         .w_in(w_in),
//         .exp_set(exp_set),
//         .done(done),
//         .exp_out(exp_out),
//         .acc_out(acc_out),
//         .active_row(active_row),
//         .active_column(active_column)
//     );

//     // integer i;
//     integer k, r, p, l;
//     initial begin
//         $dumpfile("build/mm_tb.vcd");
//         $dumpvars(0, mm_tb);

//         clk = 0;
//         rst = 1;
//         active = 0;
//         precision = 4;
//         exp_set = 5'd15;

//         $readmemh("tb/act.mem", act_mem);
//         $readmemh("tb/w.mem", w_mem);

//         #10 rst = 0;
//         #10 rst = 1;

//         wr_en_act = 1;
//         // preload activation FIFOs
//         for (k = 0; k < K; k = k + 1) begin
//             for (r = 0; r < N; r = r + 1) begin
//                 act_din[r] = act_mem[r*K + k];
//             end
//             #10;
//         end
//         wr_en_act = 0;
//         #10;

//         wr_en_w = 1;
//         // preload weight FIFOs bit-serial
//         for (k = 0; k < K; k = k + 1) begin
//             for (p = 0; p < precision; p = p + 1) begin
//                 for (r = 0; r < N; r = r + 1) begin
//                     w_din[r] = w_mem[(r*K + k)*precision + p];
//                 end
//                 #10;
//             end
//         end
//         wr_en_w = 0;
//         #20;
        
//         for (k = 0; k < K*precision; k = k + 1) begin
//             active = 1;
//             #10;
//         end
//         active = 0;
        

//         #200;
//         $display("Systolic completed:");
//         for (r = 0; r < N*N; r = r + 1) begin
//             $display("acc_out[%0d] = %h", r, acc_out[r]);
//         end

//         $finish;
//     end

    
// always @(posedge done) begin
//     $display("==== [DONE asserted] Checking Outputs ====");
//     for (l = 0; l < N*N; l= l + 1) begin
//         if (acc_out[l] !== expected_out[l])
//             $display("Mismatch at PE[%0d][%0d]: got %h, expected %h", l/N, l%N, acc_out[l], expected_out[l]);
//         else
//             $display("PE[%0d][%0d] correct: %h", l/N, l%N, acc_out[l]);
//     end
//     $display("==========================================");
// end


// endmodule