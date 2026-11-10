`timescale 1ns/1ps
module tb_systolic_array;
    localparam int N      = 4;
    localparam int DATA_W = 8;
    localparam int ACC_W  = 18;
    localparam int RANDOM_CASES = 100;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst_n, start;
    logic [N*N*DATA_W-1:0] a_matrix, b_matrix;
    wire busy, done;
    wire [N*N*ACC_W-1:0] c_matrix;

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .busy(busy), .done(done), .c_matrix(c_matrix)
    );

    task automatic run_case(input integer case_id);
        integer a_val[0:N*N-1];
        integer b_val[0:N*N-1];
        integer r, c, k, idx, expected, observed, timeout;
        begin
            for (idx=0; idx<N*N; idx=idx+1) begin
                case (case_id)
                    0: begin a_val[idx]=0; b_val[idx]=0; end
                    1: begin
                        a_val[idx]=(idx/N == idx%N) ? 1 : 0;
                        b_val[idx]=(idx/N == idx%N) ? 1 : 0;
                    end
                    2: begin a_val[idx]=127;  b_val[idx]=127;  end
                    3: begin a_val[idx]=-128; b_val[idx]=-128; end
                    4: begin
                        a_val[idx]=(idx%2 == 0) ? -128 : 127;
                        b_val[idx]=(idx%3 == 0) ? 127 : -128;
                    end
                    default: begin
                        a_val[idx]=$urandom_range(0,255)-128;
                        b_val[idx]=$urandom_range(0,255)-128;
                    end
                endcase
            end

            @(negedge clk);
            for (idx=0; idx<N*N; idx=idx+1) begin
                a_matrix[DATA_W*idx +: DATA_W] = a_val[idx][7:0];
                b_matrix[DATA_W*idx +: DATA_W] = b_val[idx][7:0];
            end
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while (done !== 1'b1 && timeout < 20) begin
                @(posedge clk);
                #1; // Observe results after nonblocking assignments.
                timeout = timeout + 1;
            end
            if (done !== 1'b1)
                $fatal(1, "TIMEOUT in test %0d", case_id);

            for (r=0; r<N; r=r+1) begin
                for (c=0; c<N; c=c+1) begin
                    expected = 0;
                    for (k=0; k<N; k=k+1)
                        expected = expected + a_val[r*N+k]*b_val[k*N+c];
                    observed = $signed(c_matrix[ACC_W*(r*N+c) +: ACC_W]);
                    if (observed !== expected)
                        $fatal(1, "FAIL test %0d C[%0d,%0d]: got %0d, expected %0d",
                               case_id, r, c, observed, expected);
                end
            end
        end
    endtask

    initial begin
        rst_n=1'b0;
        start=1'b0;
        a_matrix='0;
        b_matrix='0;
        repeat (4) @(negedge clk);
        rst_n=1'b1;
        for (int test_id=0; test_id<5+RANDOM_CASES; test_id++) begin
            run_case(test_id);
        end
        $display("PASS: 5 directed + %0d random matrix tests", RANDOM_CASES);
        $finish;
    end
endmodule
