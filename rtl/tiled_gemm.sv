// Packed, row-major GEMM wrapper. Entire operands are captured in registers;
// a single systolic tile is reused across output blocks and K partitions.
module tiled_gemm #(
    parameter int M=3, K=5, N=7, TILE=4, DATA_W=8,
    parameter int OUT_W=2*DATA_W+$clog2(K)
) (
    input logic clk, rst_n, start,
    input logic [M*K*DATA_W-1:0] a_matrix,
    input logic [K*N*DATA_W-1:0] b_matrix,
    output logic busy, done,
    output logic [M*N*OUT_W-1:0] c_matrix
);
    localparam int TILE_ACC_W=2*DATA_W+$clog2(TILE);
    typedef enum logic [1:0] {IDLE, LAUNCH, WAIT_RESULT} state_t;
    state_t state;
    logic [M*K*DATA_W-1:0] a_reg;
    logic [K*N*DATA_W-1:0] b_reg;
    logic [TILE*TILE*DATA_W-1:0] tile_a, tile_b;
    wire [TILE*TILE*TILE_ACC_W-1:0] tile_c;
    wire tile_busy, tile_done;
    wire tile_start = (state == LAUNCH);
    int unsigned row_base, col_base, k_base;

    always_comb begin
        tile_a='0;
        tile_b='0;
        for (int r=0; r<TILE; r++) begin
            for (int c=0; c<TILE; c++) begin
                if (row_base+r<M && k_base+c<K)
                    tile_a[DATA_W*(r*TILE+c) +: DATA_W] =
                        a_reg[DATA_W*((row_base+r)*K+k_base+c) +: DATA_W];
                if (k_base+r<K && col_base+c<N)
                    tile_b[DATA_W*(r*TILE+c) +: DATA_W] =
                        b_reg[DATA_W*((k_base+r)*N+col_base+c) +: DATA_W];
            end
        end
    end

    systolic_array #(.N(TILE), .DATA_W(DATA_W), .ACC_W(TILE_ACC_W)) tile (
        .clk(clk), .rst_n(rst_n), .start(tile_start),
        .a_matrix(tile_a), .b_matrix(tile_b),
        .busy(tile_busy), .done(tile_done), .c_matrix(tile_c)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE;
            a_reg<='0;
            b_reg<='0;
            c_matrix<='0;
            row_base<=0;
            col_base<=0;
            k_base<=0;
            busy<=0;
            done<=0;
        end else begin
            done<=0;
            case (state)
                IDLE: if (start) begin
                    a_reg<=a_matrix;
                    b_reg<=b_matrix;
                    c_matrix<='0;
                    row_base<=0;
                    col_base<=0;
                    k_base<=0;
                    busy<=1;
                    state<=LAUNCH;
                end
                LAUNCH: state<=WAIT_RESULT;
                WAIT_RESULT: if (tile_done) begin
                    for (int r=0; r<TILE; r++) begin
                        for (int c=0; c<TILE; c++) begin
                            if (row_base+r<M && col_base+c<N)
                                c_matrix[OUT_W*((row_base+r)*N+col_base+c) +: OUT_W] <=
                                    $signed(c_matrix[OUT_W*((row_base+r)*N+col_base+c) +: OUT_W]) +
                                    $signed(tile_c[TILE_ACC_W*(r*TILE+c) +: TILE_ACC_W]);
                        end
                    end
                    if (k_base+TILE<K) begin
                        k_base<=k_base+TILE;
                        state<=LAUNCH;
                    end else if (col_base+TILE<N) begin
                        k_base<=0;
                        col_base<=col_base+TILE;
                        state<=LAUNCH;
                    end else if (row_base+TILE<M) begin
                        k_base<=0;
                        col_base<=0;
                        row_base<=row_base+TILE;
                        state<=LAUNCH;
                    end else begin
                        busy<=0;
                        done<=1;
                        state<=IDLE;
                    end
                end
                default: begin state<=IDLE; busy<=0; end
            endcase
        end
    end
endmodule
