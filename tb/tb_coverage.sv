
`timescale 1ns/1ps

// ============================================================
// INT8 SYSTOLIC ARRAY - FUNCTIONAL COVERAGE MONITOR
// ============================================================

module systolic_coverage #(
    parameter integer N = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 18
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire busy,
    input wire done,

    input wire [N*N*DATA_W-1:0] a_matrix,
    input wire [N*N*DATA_W-1:0] b_matrix,

    input wire [N*N*ACC_W-1:0] c_matrix
);

    // --------------------------------------------------------
    // 1. Input coverage counters
    // --------------------------------------------------------

    integer zero_matrix_hits = 0;
    integer identity_hits = 0;
    integer positive_extreme_hits = 0;
    integer negative_extreme_hits = 0;
    integer mixed_sign_hits = 0;
    integer zero_operand_hits = 0;

    // --------------------------------------------------------
    // 2. Protocol coverage counters
    // --------------------------------------------------------

    integer launch_hits = 0;
    integer completion_hits = 0;
    integer busy_start_hits = 0;
    integer reset_abort_hits = 0;
    integer idle_hold_hits = 0;

    // --------------------------------------------------------
    // 3. Output coverage counters
    // --------------------------------------------------------

    integer positive_output_hits = 0;
    integer negative_output_hits = 0;
    integer zero_output_hits = 0;

    // --------------------------------------------------------
    // 4. Internal monitoring variables
    // --------------------------------------------------------

    integer idx;
    integer a_value;
    integer b_value;
    integer c_value;

    integer positive_count;
    integer negative_count;
    integer zero_count;

    reg all_zero;
    reg identity;
    reg all_positive_extreme;
    reg all_negative_extreme;

    reg sampled_busy;
    reg sampled_start;

    reg [N*N*ACC_W-1:0] previous_output;

    reg job_active = 0;

    integer covered_bins;


    // ========================================================
    // 5. RESET COVERAGE
    // ========================================================

    always @(negedge rst_n) begin

        if (job_active) begin

            reset_abort_hits = reset_abort_hits + 1;

            job_active = 0;

        end

    end


    // ========================================================
    // 6. CLOCKED COVERAGE SAMPLING
    // ========================================================

    always @(posedge clk) begin

        // Sample signals before RTL nonblocking updates
        sampled_busy = busy;
        sampled_start = start;
        previous_output = c_matrix;

        if (rst_n === 1'b1) begin

            // =================================================
            // 7. ACCEPTED TRANSACTION COVERAGE
            // =================================================

            if (!sampled_busy && sampled_start) begin

                launch_hits = launch_hits + 1;

                job_active = 1;

                all_zero = 1;
                identity = 1;
                all_positive_extreme = 1;
                all_negative_extreme = 1;

                positive_count = 0;
                negative_count = 0;
                zero_count = 0;

                for (idx=0; idx<N*N; idx=idx+1) begin

                    a_value = $signed(
                        a_matrix[DATA_W*idx +: DATA_W]
                    );

                    b_value = $signed(
                        b_matrix[DATA_W*idx +: DATA_W]
                    );

                    // Track operand signs
                    if (a_value > 0)
                        positive_count++;

                    if (b_value > 0)
                        positive_count++;

                    if (a_value < 0)
                        negative_count++;

                    if (b_value < 0)
                        negative_count++;

                    if (a_value == 0)
                        zero_count++;

                    if (b_value == 0)
                        zero_count++;

                    // All-zero input matrices
                    if (a_value != 0 || b_value != 0)
                        all_zero = 0;

                    // Identity matrix pair
                    if ((idx/N) == (idx%N)) begin

                        if (a_value != 1 || b_value != 1)
                            identity = 0;

                    end else begin

                        if (a_value != 0 || b_value != 0)
                            identity = 0;

                    end

                    // Maximum positive INT8
                    if (a_value != 127 || b_value != 127)
                        all_positive_extreme = 0;

                    // Minimum negative INT8
                    if (a_value != -128 || b_value != -128)
                        all_negative_extreme = 0;

                end

                // Record observed input bins
                if (all_zero)
                    zero_matrix_hits++;

                if (identity)
                    identity_hits++;

                if (all_positive_extreme)
                    positive_extreme_hits++;

                if (all_negative_extreme)
                    negative_extreme_hits++;

                if (positive_count > 0 &&
                    negative_count > 0)
                    mixed_sign_hits++;

                if (zero_count > 0)
                    zero_operand_hits++;

            end


            // =================================================
            // 8. BUSY-START PROTOCOL COVERAGE
            // =================================================

            if (sampled_busy && sampled_start)
                busy_start_hits++;


            // Wait for DUT register updates
            #1;


            // =================================================
            // 9. COMPLETION AND OUTPUT COVERAGE
            // =================================================

            if (sampled_busy &&
                busy === 1'b0 &&
                done === 1'b1) begin

                completion_hits++;

                job_active = 0;

                // Classify each output element
                for (idx=0; idx<N*N; idx=idx+1) begin

                    c_value = $signed(
                        c_matrix[ACC_W*idx +: ACC_W]
                    );

                    if (c_value > 0)
                        positive_output_hits++;

                    else if (c_value < 0)
                        negative_output_hits++;

                    else
                        zero_output_hits++;

                end

            end


            // =================================================
            // 10. IDLE OUTPUT RETENTION COVERAGE
            // =================================================

            if (!sampled_busy &&
                !sampled_start &&
                busy === 1'b0 &&
                done === 1'b0 &&
                c_matrix === previous_output) begin

                idle_hold_hits++;

            end

        end

    end


    // ========================================================
    // 11. FINAL FUNCTIONAL COVERAGE REPORT
    // ========================================================

    final begin

        covered_bins = 0;

        // Input bins: 6
        if (zero_matrix_hits > 0) covered_bins++;
        if (identity_hits > 0) covered_bins++;
        if (positive_extreme_hits > 0) covered_bins++;
        if (negative_extreme_hits > 0) covered_bins++;
        if (mixed_sign_hits > 0) covered_bins++;
        if (zero_operand_hits > 0) covered_bins++;

        // Protocol bins: 5
        if (launch_hits > 0) covered_bins++;
        if (completion_hits > 0) covered_bins++;
        if (busy_start_hits > 0) covered_bins++;
        if (reset_abort_hits > 0) covered_bins++;
        if (idle_hold_hits > 0) covered_bins++;

        // Output bins: 3
        if (positive_output_hits > 0) covered_bins++;
        if (negative_output_hits > 0) covered_bins++;
        if (zero_output_hits > 0) covered_bins++;

        $display("");
        $display("========================================");
        $display(" INT8 SYSTOLIC ARRAY COVERAGE REPORT");
        $display("========================================");

        $display("");
        $display("INPUT COVERAGE");
        $display("----------------------------------------");
        $display("Zero matrices        : %0d",
                 zero_matrix_hits);
        $display("Identity matrices    : %0d",
                 identity_hits);
        $display("Positive extremes    : %0d",
                 positive_extreme_hits);
        $display("Negative extremes    : %0d",
                 negative_extreme_hits);
        $display("Mixed-sign inputs    : %0d",
                 mixed_sign_hits);
        $display("Zero-containing input: %0d",
                 zero_operand_hits);

        $display("");
        $display("PROTOCOL COVERAGE");
        $display("----------------------------------------");
        $display("Accepted launches    : %0d",
                 launch_hits);
        $display("Completed jobs       : %0d",
                 completion_hits);
        $display("Start during busy    : %0d",
                 busy_start_hits);
        $display("Reset during job     : %0d",
                 reset_abort_hits);
        $display("Idle output hold     : %0d",
                 idle_hold_hits);

        $display("");
        $display("OUTPUT COVERAGE");
        $display("----------------------------------------");
        $display("Positive outputs     : %0d",
                 positive_output_hits);
        $display("Negative outputs     : %0d",
                 negative_output_hits);
        $display("Zero outputs         : %0d",
                 zero_output_hits);

        $display("");
        $display("========================================");
        $display("DEFINED COVERAGE BINS");
        $display("========================================");

        $display("Bins covered : %0d / 14",
                 covered_bins);

        $display("Bin coverage : %0d%%",
                 (covered_bins*100)/14);

        if (covered_bins == 14)
            $display("PASS: All defined bins exercised");
        else
            $display("INCOMPLETE: Some bins not exercised");

        $display("----------------------------------------");
        $display("This is manually tracked functional");
        $display("coverage, not full coverage closure.");
        $display("========================================");

    end

endmodule


// ============================================================
// 12. COVERAGE TESTBENCH WRAPPER
// ============================================================
//
// Runs the existing advanced testbench without modifying it.
// Connects a separate coverage monitor to its signals.
//
// ============================================================

module tb_coverage #(parameter integer RANDOM_CASES = 200);

    tb_advanced #(.RANDOM_CASES(RANDOM_CASES)) testbench();

    systolic_coverage #(
        .N(4),
        .DATA_W(8),
        .ACC_W(18)
    ) coverage (
        .clk(testbench.clk),
        .rst_n(testbench.rst_n),
        .start(testbench.start),
        .busy(testbench.busy),
        .done(testbench.done),
        .a_matrix(testbench.a_matrix),
        .b_matrix(testbench.b_matrix),
        .c_matrix(testbench.c_matrix)
    );

endmodule
