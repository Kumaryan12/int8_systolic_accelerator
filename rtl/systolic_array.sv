// One N x N output tile: C = A * B (with K=N).
// Flattened row-major: element [row][col] occupies bits
// [W*(row*N+col) +: W]. A and B are signed 8-bit elements.
// Single job at a time; hold start for exactly one accepted clock edge.
module systolic_array #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 2*DATA_W + $clog2(N)
) (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              start,
    input  logic [N*N*DATA_W-1:0]             a_matrix,
    input  logic [N*N*DATA_W-1:0]             b_matrix,
    output logic                              busy,
    output logic                              done,
    output wire  [N*N*ACC_W-1:0]              c_matrix
);
    // Products for output C[i,j] occur at t=k+i+j, k=0,...,N-1.
    // The last product is consumed at t=3*N-3, so 3*N-2
    // rising-edge compute cycles are needed after matrix capture.
    localparam int COMPUTE_CYCLES = 3*N-2;
    localparam int COUNT_W = $clog2(COMPUTE_CYCLES+1);

    logic [N*N*DATA_W-1:0] a_reg, b_reg;
    logic [COUNT_W-1:0] cycle_count;
    logic clear_array;

    logic signed [DATA_W-1:0] a_edge [0:N-1];
    logic signed [DATA_W-1:0] b_edge [0:N-1];
    wire  signed [DATA_W-1:0] a_link [0:N-1][0:N];
    wire  signed [DATA_W-1:0] b_link [0:N][0:N-1];

    assign clear_array = start && !busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg       <= '0;
            b_reg       <= '0;
            cycle_count <= '0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                a_reg       <= a_matrix;
                b_reg       <= b_matrix;
                cycle_count <= '0;
                busy        <= 1'b1;
            end else if (busy) begin
                if (cycle_count == COMPUTE_CYCLES-1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end
        end
    end

    // Skew row i of A by i cycles and column j of B by j cycles.
    // Zero padding prevents products outside the valid K range.
    always_comb begin
        for (int r=0; r<N; r++) begin
            a_edge[r] = '0;
            if (busy && (int'(cycle_count) >= r) &&
                        (int'(cycle_count) < r+N)) begin
                a_edge[r] = $signed(a_reg[
                    DATA_W*(r*N + (int'(cycle_count)-r)) +: DATA_W]);
            end
        end
        for (int c=0; c<N; c++) begin
            b_edge[c] = '0;
            if (busy && (int'(cycle_count) >= c) &&
                        (int'(cycle_count) < c+N)) begin
                b_edge[c] = $signed(b_reg[
                    DATA_W*((int'(cycle_count)-c)*N + c) +: DATA_W]);
            end
        end
    end

    for (genvar r=0; r<N; r++) begin : GEN_ROWS
        assign a_link[r][0] = a_edge[r];
        for (genvar c=0; c<N; c++) begin : GEN_COLS
            if (r == 0) begin : GEN_TOP
                assign b_link[0][c] = b_edge[c];
            end
            mac_pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                .clk(clk),
                .rst_n(rst_n),
                .clear(clear_array),
                .enable(busy),
                .a_in(a_link[r][c]),
                .b_in(b_link[r][c]),
                .a_out(a_link[r][c+1]),
                .b_out(b_link[r+1][c]),
                .acc_out(c_matrix[ACC_W*(r*N+c) +: ACC_W])
            );
        end
    end
endmodule
