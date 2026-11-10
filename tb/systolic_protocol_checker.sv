
`timescale 1ns/1ps

module systolic_protocol_checker #(
    parameter integer N = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 2*DATA_W + $clog2(N)
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire busy,
    input wire done,
    input wire [N*N*ACC_W-1:0] c_matrix
);

    localparam integer COMPUTE_CYCLES = 3*N - 2;

    integer cycles_seen = 0;
    integer launches = 0;
    integer completions = 0;
    integer resets_during_job = 0;

    reg job_active = 0;

    reg previous_busy;
    reg previous_done;
    reg previous_start;

    reg [N*N*ACC_W-1:0] previous_output;

    // Asynchronous reset assertions
    always @(negedge rst_n) begin

        if (job_active)
            resets_during_job = resets_during_job + 1;

        job_active = 0;
        cycles_seen = 0;

        #1;

        assert (busy === 1'b0)
        else $fatal(1,
            "ASSERTION FAILED: busy not cleared by reset");

        assert (done === 1'b0)
        else $fatal(1,
            "ASSERTION FAILED: done not cleared by reset");

        assert (c_matrix === '0)
        else $fatal(1,
            "ASSERTION FAILED: outputs not cleared by reset");

    end

    // Clocked protocol assertions
    always @(posedge clk) begin

        // Capture signals before sequential RTL updates
        previous_busy   = busy;
        previous_done   = done;
        previous_start  = start;
        previous_output = c_matrix;

        if (!rst_n) begin

            job_active = 0;
            cycles_seen = 0;

            #1;

            assert (busy === 1'b0 &&
                    done === 1'b0 &&
                    c_matrix === '0)
            else $fatal(1,
                "ASSERTION FAILED: reset state incorrect");

        end else begin

            // Wait for nonblocking assignments to settle
            #1;

            // Assertion 1: Control outputs must be known
            assert ((busy === 1'b0 || busy === 1'b1) &&
                    (done === 1'b0 || done === 1'b1))
            else $fatal(1,
                "ASSERTION FAILED: unknown control signal");

            // Assertion 2: busy and done cannot be high together
            assert (!(busy === 1'b1 && done === 1'b1))
            else $fatal(1,
                "ASSERTION FAILED: busy and done simultaneously high");

            // Assertion 3: A valid start launches a transaction
            if (!previous_busy && previous_start) begin

                launches = launches + 1;
                job_active = 1;
                cycles_seen = 0;

                assert (busy === 1'b1 &&
                        done === 1'b0)
                else $fatal(1,
                    "ASSERTION FAILED: valid start not accepted");

                // Starting a job clears all PE accumulators
                assert (c_matrix === '0)
                else $fatal(1,
                    "ASSERTION FAILED: accumulators not cleared");

            end

            // Assertions for an active computation
            else if (previous_busy) begin

                assert (job_active)
                else $fatal(1,
                    "ASSERTION FAILED: busy without active job");

                cycles_seen = cycles_seen + 1;

                // Assertion 4: No early completion
                if (cycles_seen < COMPUTE_CYCLES) begin

                    assert (busy === 1'b1 &&
                            done === 1'b0)
                    else $fatal(1,
                        "ASSERTION FAILED: premature completion");

                end

                // Assertion 5: Exact completion latency
                else if (cycles_seen == COMPUTE_CYCLES) begin

                    assert (busy === 1'b0 &&
                            done === 1'b1)
                    else $fatal(1,
                        "ASSERTION FAILED: incorrect completion latency");

                    completions = completions + 1;
                    job_active = 0;

                end

                // Assertion 6: Computation must not overrun
                else begin

                    $fatal(1,
                        "ASSERTION FAILED: computation exceeded latency");

                end

            end

            // Assertions for the idle state
            else begin

                // Assertion 7: No spontaneous computation
                assert (busy === 1'b0 &&
                        done === 1'b0)
                else $fatal(1,
                    "ASSERTION FAILED: spontaneous busy/done");

                // Assertion 8: Output holds its previous result
                assert (c_matrix === previous_output)
                else $fatal(1,
                    "ASSERTION FAILED: output changed while idle");

            end

            // Assertion 9: done must be a one-cycle pulse
            if (previous_done) begin

                assert (done === 1'b0)
                else $fatal(1,
                    "ASSERTION FAILED: done pulse longer than one cycle");

            end

        end
    end

    // Simulation summary
    final begin

        $display("====================================");
        $display("PROTOCOL ASSERTION CHECKER");
        $display("Accepted launches : %0d", launches);
        $display("Completed jobs    : %0d", completions);
        $display("Aborted by reset  : %0d", resets_during_job);
        $display("Assertions        : No failures reported");
        $display("====================================");

    end

endmodule
