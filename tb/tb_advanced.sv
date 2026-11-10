
`timescale 1ns/1ps

module tb_advanced;

    parameter integer N = 4;
    parameter integer DATA_W = 8;
    parameter integer ACC_W = 2*DATA_W + $clog2(N);
    parameter integer RANDOM_CASES = 200;

    localparam integer COMPUTE_CYCLES = 3*N - 2;

    // Clock generation
    reg clk = 0;
    always #5 clk = ~clk;

    // Control signals
    reg rst_n = 0;
    reg start = 0;

    // Matrix inputs
    reg [N*N*DATA_W-1:0] a_matrix = 0;
    reg [N*N*DATA_W-1:0] b_matrix = 0;

    // DUT outputs
    wire busy, done;
    wire [N*N*ACC_W-1:0] c_matrix;

    // Golden reference matrices
    integer a_expected [0:N*N-1];
    integer b_expected [0:N*N-1];

    // Random seed
    reg [31:0] rng_state = 32'd20261110;

    // Verification counters
    integer jobs_passed = 0;
    integer busy_start_checks = 0;
    integer hold_checks = 0;
    integer reset_checks = 0;
    integer latency_checks = 0;

    // Scenario counters
    integer negative_seen = 0;
    integer positive_seen = 0;
    integer zero_seen = 0;


    // =========================================================
    // 1. DEVICE UNDER TEST
    // =========================================================

    systolic_array #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .busy(busy),
        .done(done),
        .c_matrix(c_matrix)
    );


    // =========================================================
    // 2. PROTOCOL ASSERTION CHECKER
    // =========================================================

    systolic_protocol_checker #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) protocol_checker (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .c_matrix(c_matrix)
    );


    // =========================================================
    // 3. DETERMINISTIC RANDOM NUMBER GENERATOR
    // =========================================================

    function integer rand_int8;
        begin
            rng_state = rng_state * 32'd1664525
                      + 32'd1013904223;

            rand_int8 = int'(rng_state[23:16]) - 128;
        end
    endfunction


    // =========================================================
    // 4. MATRIX GENERATION
    // =========================================================

    task automatic prepare_matrix(input integer id);

        integer idx, r, c;

        begin

            for (idx=0; idx<N*N; idx=idx+1) begin

                r = idx/N;
                c = idx%N;

                case (id)

                    // All-zero matrices
                    0: begin
                        a_expected[idx] = 0;
                        b_expected[idx] = 0;
                    end

                    // Identity matrices
                    1: begin
                        a_expected[idx] = (r==c) ? 1 : 0;
                        b_expected[idx] = (r==c) ? 1 : 0;
                    end

                    // Maximum positive INT8
                    2: begin
                        a_expected[idx] = 127;
                        b_expected[idx] = 127;
                    end

                    // Minimum negative INT8
                    3: begin
                        a_expected[idx] = -128;
                        b_expected[idx] = -128;
                    end

                    // Mixed-sign extremes
                    4: begin
                        a_expected[idx] =
                            (idx%2==0) ? -128 : 127;

                        b_expected[idx] =
                            (idx%3==0) ? 127 : -128;
                    end

                    // Negative identity multiplied by
                    // positive identity
                    5: begin
                        a_expected[idx] =
                            (r==c) ? -128 : 0;

                        b_expected[idx] =
                            (r==c) ? 127 : 0;
                    end

                    // Random INT8 matrices
                    default: begin
                        a_expected[idx] = rand_int8();
                        b_expected[idx] = rand_int8();
                    end

                endcase

                // Track operand categories
                if (a_expected[idx]<0 || b_expected[idx]<0)
                    negative_seen++;

                if (a_expected[idx]>0 || b_expected[idx]>0)
                    positive_seen++;

                if (a_expected[idx]==0 || b_expected[idx]==0)
                    zero_seen++;

                // Pack matrices into RTL input vectors
                a_matrix[DATA_W*idx +: DATA_W] =
                    a_expected[idx];

                b_matrix[DATA_W*idx +: DATA_W] =
                    b_expected[idx];

            end

        end

    endtask


    // =========================================================
    // 5. GOLDEN REFERENCE SCOREBOARD
    // =========================================================

    task automatic check_result(input integer id);

        integer r, c, k;
        integer expected, actual;

        begin

            for (r=0; r<N; r=r+1) begin

                for (c=0; c<N; c=c+1) begin

                    expected = 0;

                    // Reference matrix multiplication
                    for (k=0; k<N; k=k+1) begin

                        expected +=
                            a_expected[r*N+k]
                            * b_expected[k*N+c];

                    end

                    // Read result from hardware
                    actual = $signed(
                        c_matrix[ACC_W*(r*N+c) +: ACC_W]
                    );

                    // Compare actual and expected values
                    if (actual !== expected) begin

                        $fatal(
                            1,
                            "FAIL case=%0d C[%0d,%0d]=%0d expected=%0d",
                            id,
                            r,
                            c,
                            actual,
                            expected
                        );

                    end

                end

            end

        end

    endtask


    // =========================================================
    // 6. COMPLETE TRANSACTION VERIFICATION
    // =========================================================

    task automatic run_job(
        input integer id,
        input integer inject_busy_start
    );

        integer t;
        reg [N*N*ACC_W-1:0] snapshot;

        begin

            @(negedge clk);

            // Check that accelerator is idle
            if (busy !== 0 || done !== 0)
                $fatal(1, "Accelerator not idle");

            // Generate test inputs
            prepare_matrix(id);

            // Start computation
            start = 1;

            @(posedge clk);
            #1;

            // Check successful launch
            if (busy !== 1 || done !== 0)
                $fatal(
                    1,
                    "Launch failed for case %0d",
                    id
                );

            @(negedge clk);
            start = 0;

            // Monitor complete computation
            for (t=0; t<COMPUTE_CYCLES; t=t+1) begin

                // Attempt another start while busy
                if (inject_busy_start && t==2) begin

                    start = 1;

                    // Change external inputs
                    a_matrix = '1;
                    b_matrix = '1;

                end else begin

                    start = 0;

                end

                @(posedge clk);
                #1;

                // Check exact completion timing
                if (t == COMPUTE_CYCLES-1) begin

                    if (busy !== 0 || done !== 1)
                        $fatal(
                            1,
                            "Incorrect done timing"
                        );

                    latency_checks++;

                end else begin

                    if (busy !== 1 || done !== 0)
                        $fatal(
                            1,
                            "Incorrect busy/done behavior"
                        );

                end

                if (t < COMPUTE_CYCLES-1)
                    @(negedge clk);

            end

            start = 0;

            // Check complete result matrix
            check_result(id);

            if (inject_busy_start)
                busy_start_checks++;

            // Save current output
            snapshot = c_matrix;

            @(posedge clk);
            #1;

            // Verify output retention
            if (done !== 0 ||
                busy !== 0 ||
                c_matrix !== snapshot)
                $fatal(
                    1,
                    "Output retention failed"
                );

            hold_checks++;
            jobs_passed++;

        end

    endtask


    // =========================================================
    // 7. ASYNCHRONOUS RESET DURING COMPUTATION
    // =========================================================

    task automatic reset_mid_job;

        begin

            @(negedge clk);

            // Start transaction
            prepare_matrix(3);
            start = 1;

            @(posedge clk);
            #1;

            if (busy !== 1)
                $fatal(
                    1,
                    "Reset test launch failed"
                );

            @(negedge clk);
            start = 0;

            // Let computation run for three cycles
            repeat (3) @(negedge clk);

            // Assert reset during computation
            rst_n = 0;

            #1;

            // Verify asynchronous reset
            if (busy !== 0 ||
                done !== 0 ||
                c_matrix !== '0)
                $fatal(
                    1,
                    "Asynchronous reset failed"
                );

            repeat (2) @(negedge clk);

            // Release reset
            rst_n = 1;

            @(posedge clk);
            #1;

            // Ensure accelerator remains idle
            if (busy !== 0 ||
                done !== 0 ||
                c_matrix !== '0)
                $fatal(
                    1,
                    "Activity detected after reset"
                );

            reset_checks++;

        end

    endtask


    // =========================================================
    // 8. MAIN VERIFICATION SEQUENCE
    // =========================================================

    initial begin

        // Allow random seed override
        if ($value$plusargs("SEED=%d", rng_state))
            $display(
                "Regression seed=%0d",
                rng_state
            );

        // Initial reset sequence
        repeat (4) @(negedge clk);

        rst_n = 1;

        // Six directed tests + 200 randomized tests
        for (
            integer id=0;
            id<6+RANDOM_CASES;
            id=id+1
        ) begin

            run_job(id, (id%7==0));

        end

        // Test reset during active computation
        reset_mid_job();

        // Verify recovery after reset
        run_job(4, 1);


        // =====================================================
        // 9. VERIFICATION COMPLETENESS CHECKS
        // =====================================================

        if (jobs_passed != 7+RANDOM_CASES ||
            busy_start_checks == 0 ||
            hold_checks == 0 ||
            reset_checks != 1 ||
            latency_checks != jobs_passed ||
            negative_seen == 0 ||
            positive_seen == 0 ||
            zero_seen == 0) begin

            $fatal(
                1,
                "Required scenarios not exercised"
            );

        end


        // =====================================================
        // 10. FINAL TEST REPORT
        // =====================================================

        $display("");
        $display("========================================");
        $display(" ADVANCED RTL VERIFICATION REPORT");
        $display("========================================");

        $display(
            "Total successful jobs : %0d",
            jobs_passed
        );

        $display(
            "Busy-start checks      : %0d",
            busy_start_checks
        );

        $display(
            "Output retention checks: %0d",
            hold_checks
        );

        $display(
            "Reset checks           : %0d",
            reset_checks
        );

        $display(
            "Latency checks         : %0d",
            latency_checks
        );

        $display("----------------------------------------");

        $display(
            "Positive operand cases : %0d",
            positive_seen
        );

        $display(
            "Negative operand cases : %0d",
            negative_seen
        );

        $display(
            "Zero operand cases     : %0d",
            zero_seen
        );

        $display("----------------------------------------");

        $display("PASS: Advanced verification completed");
        $display("NOTE: Full functional coverage not yet measured.");
        $display("========================================");

        $finish;

    end

endmodule
