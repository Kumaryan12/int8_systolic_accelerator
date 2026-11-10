`timescale 1ns/1ps
module tb_tiled_gemm #(
    parameter int M=3, K=5, N=7, TILE=4, RANDOM_CASES=30
);
    localparam int DATA_W=8, OUT_W=16+$clog2(K);
    localparam int TILES=((M+TILE-1)/TILE)*((N+TILE-1)/TILE)*((K+TILE-1)/TILE);
    localparam int LATENCY=TILES*(3*TILE);
    reg clk=0, rst_n=0, start=0;
    always #5 clk=~clk;
    reg [M*K*8-1:0] a_matrix='0;
    reg [K*N*8-1:0] b_matrix='0;
    wire busy, done;
    wire [M*N*OUT_W-1:0] c_matrix;
    integer av[0:M*K-1], bv[0:K*N-1];
    reg [31:0] rng=20261110;
    integer jobs=0;

    tiled_gemm #(.M(M), .K(K), .N(N), .TILE(TILE)) dut (.*);

    function integer random_int8;
        rng=rng*32'd1664525+32'd1013904223;
        random_int8=int'(rng[23:16])-128;
    endfunction

    task automatic prepare(input integer id);
        for (integer i=0; i<M*K; i++) begin
            case(id)
                0: av[i]=0;
                1: av[i]=-128;
                2: av[i]=(i%2) ? 127 : -128;
                3: av[i]=127;
                default: av[i]=random_int8();
            endcase
            a_matrix[8*i +: 8]=av[i];
        end
        for (integer i=0; i<K*N; i++) begin
            case(id)
                0: bv[i]=0;
                1: bv[i]=-128;
                2: bv[i]=(i%3) ? -128 : 127;
                3: bv[i]=127;
                default: bv[i]=random_int8();
            endcase
            b_matrix[8*i +: 8]=bv[i];
        end
    endtask

    task automatic run_job(input integer id);
        longint signed expected, actual;
        reg [M*N*OUT_W-1:0] retained;
        @(negedge clk);
        prepare(id);
        start=1;
        @(posedge clk); #1;
        if (!busy || done || c_matrix !== '0) $fatal(1,"GEMM launch failed");
        @(negedge clk); start=0;
        for (integer cycle=0; cycle<LATENCY; cycle++) begin
            // External changes and a busy start must not corrupt captured inputs.
            if (cycle==2) begin start=1; a_matrix='1; b_matrix='1; end
            else start=0;
            @(posedge clk); #1;
            if (cycle==LATENCY-1) begin
                if (busy || !done) $fatal(1,"GEMM latency/completion failed");
            end else if (!busy || done) $fatal(1,"GEMM completed early");
            if (cycle<LATENCY-1) @(negedge clk);
        end
        start=0;
        for (integer r=0; r<M; r++) begin
            for (integer c=0; c<N; c++) begin
                expected=0;
                for (integer k=0; k<K; k++) expected+=av[r*K+k]*bv[k*N+c];
                actual=$signed(c_matrix[OUT_W*(r*N+c) +: OUT_W]);
                if (actual !== expected)
                    $fatal(1,"GEMM %0dx%0dx%0d id=%0d C[%0d,%0d]=%0d expected=%0d",M,K,N,id,r,c,actual,expected);
            end
        end
        retained=c_matrix;
        repeat (2) begin
            @(posedge clk); #1;
            if (busy || done || c_matrix !== retained) $fatal(1,"GEMM idle hold failed");
        end
        jobs++;
    endtask

    task automatic reset_abort(input integer edges);
        @(negedge clk); prepare(1); start=1;
        @(negedge clk); start=0;
        repeat (edges) @(negedge clk);
        // Deliberately assert between clock edges.
        #2; rst_n=0; #1;
        if (busy || done || c_matrix !== '0) $fatal(1,"GEMM async abort failed");
        repeat (2) @(negedge clk);
        rst_n=1;
        run_job(2);
    endtask

    initial begin
        if ($value$plusargs("SEED=%d",rng)) begin end
        $display("Tiled GEMM shape=%0dx%0dx%0d seed=%0d tiles=%0d latency=%0d",M,K,N,rng,TILES,LATENCY);
        repeat (3) @(negedge clk);
        rst_n=1;
        for (integer id=0; id<4+RANDOM_CASES; id++) run_job(id);
        reset_abort(0);
        reset_abort(LATENCY/2);
        reset_abort(LATENCY-1);
        if (jobs != 7+RANDOM_CASES) $fatal(1,"GEMM job count failed");
        $display("PASS: Tiled RTL GEMM jobs=%0d output_checks=%0d reset_aborts=3",jobs,jobs*M*N);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1,"GEMM global timeout");
    end
endmodule
