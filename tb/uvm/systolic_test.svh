
`ifndef SYSTOLIC_TEST_SVH
`define SYSTOLIC_TEST_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM TEST
// ============================================================
//
// Test configuration:
// Matrix dimensions : 4 x 4
// Input precision   : Signed INT8
// Output precision  : Signed INT18
//
// Verification:
//  - 6 directed transactions
//  - 200 randomized transactions
//  - Scoreboard checking
//  - Transaction count checking
//  - Output element checking
//  - Timeout detection
//  - Final pass/fail reporting
//
// ============================================================

class systolic_test extends uvm_test;

    `uvm_component_utils(systolic_test)

    // ========================================================
    // 1. UVM ENVIRONMENT
    // ========================================================

    systolic_env env;

    // ========================================================
    // 2. TEST CONFIGURATION
    // ========================================================

    int unsigned num_random = 200;

    localparam int NUM_DIRECTED = 6;
    localparam int NUM_OUTPUTS = 16;

    int unsigned expected_transactions;
    int unsigned expected_elements;

    // Maximum extra cycles to allow the scoreboard
    // to process the final transaction.
    localparam int SCOREBOARD_TIMEOUT = 100;

    // ========================================================
    // 3. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_test",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction

    // ========================================================
    // 4. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // Optional command-line override:
        // +NUM_RANDOM=50
        //
        // Default remains 200 randomized transactions.

        void'(
            $value$plusargs(
                "NUM_RANDOM=%d",
                num_random
            )
        );

        expected_transactions =
            NUM_DIRECTED + num_random + 2;

        expected_elements =
            expected_transactions * NUM_OUTPUTS;

        // Create UVM environment
        env = systolic_env::type_id::create(
            "env",
            this
        );

        `uvm_info(
            "TEST_BUILD",
            $sformatf(
                {
                    "UVM test initialized\n",
                    "Directed transactions : %0d\n",
                    "Random transactions   : %0d\n",
                    "Expected transactions : %0d\n",
                    "Expected output checks: %0d"
                },
                NUM_DIRECTED,
                num_random,
                expected_transactions,
                expected_elements
            ),
            UVM_LOW
        )

    endfunction

    // ========================================================
    // 5. RUN PHASE
    // ========================================================

    task run_phase(uvm_phase phase);

        systolic_sequence seq;

        int unsigned wait_cycles;

        phase.raise_objection(this);

        `uvm_info(
            "TEST_START",
            "Starting INT8 systolic-array UVM verification",
            UVM_LOW
        )

        // ----------------------------------------------------
        // A. CHECK ENVIRONMENT
        // ----------------------------------------------------

        if (env == null ||
            env.agent == null ||
            env.scoreboard == null) begin

            `uvm_fatal(
                "TEST_ENV",
                "UVM environment is not initialized"
            )

        end

        // The test requires an active agent.
        if (env.agent.sequencer == null ||
            env.agent.driver == null) begin

            `uvm_fatal(
                "TEST_AGENT",
                "Active agent components are missing"
            )

        end

        // ----------------------------------------------------
        // B. CREATE TEST SEQUENCE
        // ----------------------------------------------------

        seq = systolic_sequence::type_id::create(
            "seq"
        );

        seq.num_random = num_random;

        // ----------------------------------------------------
        // C. EXECUTE VERIFICATION SEQUENCE
        // ----------------------------------------------------

        `uvm_info(
            "TEST_SEQUENCE",
            "Executing directed and randomized transactions",
            UVM_LOW
        )

        seq.start(env.agent.sequencer);

        `uvm_info(
            "TEST_SEQUENCE",
            "All sequence items have been processed by driver",
            UVM_LOW
        )

        // ----------------------------------------------------
        // D. WAIT FOR SCOREBOARD COMPLETION
        // ----------------------------------------------------

        wait_cycles = 0;

        while (
            env.scoreboard.transactions_checked
                < expected_transactions
            &&
            wait_cycles < SCOREBOARD_TIMEOUT
        ) begin

            @(posedge env.vif.clk);

            wait_cycles++;

        end

        // Allow scoreboard counters and remaining
        // simulation events to settle.
        #1;

        // ----------------------------------------------------
        // E. CHECK FOR SCOREBOARD TIMEOUT
        // ----------------------------------------------------

        if (
            env.scoreboard.transactions_checked
                != expected_transactions
        ) begin

            `uvm_fatal(
                "TEST_TIMEOUT",
                $sformatf(
                    {
                        "Scoreboard did not process all transactions\n",
                        "Expected = %0d\n",
                        "Checked  = %0d"
                    },
                    expected_transactions,
                    env.scoreboard.transactions_checked
                )
            )

        end

        // ----------------------------------------------------
        // F. CHECK TRANSACTION RESULTS
        // ----------------------------------------------------

        if (
            env.scoreboard.transactions_failed != 0
        ) begin

            `uvm_fatal(
                "TEST_FAILURE",
                $sformatf(
                    "%0d transactions failed",
                    env.scoreboard.transactions_failed
                )
            )

        end

        if (
            env.scoreboard.transactions_passed
                != expected_transactions
        ) begin

            `uvm_fatal(
                "TEST_COUNT",
                "Passed transaction count mismatch"
            )

        end

        // ----------------------------------------------------
        // G. CHECK OUTPUT ELEMENT COUNT
        // ----------------------------------------------------

        if (
            env.scoreboard.elements_checked
                != expected_elements
        ) begin

            `uvm_fatal(
                "TEST_ELEMENTS",
                $sformatf(
                    "Expected %0d output checks, observed %0d",
                    expected_elements,
                    env.scoreboard.elements_checked
                )
            )

        end

        if (
            env.scoreboard.elements_failed != 0
        ) begin

            `uvm_fatal(
                "TEST_DATA",
                "One or more matrix output elements failed"
            )

        end

        // ----------------------------------------------------
        // H. CHECK DRIVER AND MONITOR COUNTS
        // ----------------------------------------------------

        if (
            env.agent.driver.completed_transactions
                != expected_transactions
        ) begin

            `uvm_fatal(
                "DRIVER_COUNT",
                "Driver completion count mismatch"
            )

        end

        if (
            env.agent.monitor.completed_transactions
                != expected_transactions
        ) begin

            `uvm_fatal(
                "MONITOR_COUNT",
                "Monitor completion count mismatch"
            )

        end

        // ----------------------------------------------------
        // I. CHECK PROTOCOL ERRORS
        // ----------------------------------------------------

        if (
            env.scoreboard.protocol_errors != 0
        ) begin

            `uvm_fatal(
                "PROTOCOL_ERROR",
                "Scoreboard detected protocol errors"
            )

        end

        // ----------------------------------------------------
        // Both the monitor and scoreboard must observe the reset terminal event.
        if (env.agent.driver.aborted_transactions != 1 ||
            env.agent.monitor.aborted_transactions != 1 ||
            env.scoreboard.transactions_aborted != 1 ||
            env.agent.driver.busy_start_checks != 1 ||
            env.agent.monitor.accepted_transactions != expected_transactions + 1)
            `uvm_fatal("CONTROL_COVERAGE", "Required reset/busy-start scenarios or abort bookkeeping missing")

        `uvm_info("CONTROL_PASS", "Reset abort=1; busy-start=1; post-reset scoreboard recovery passed", UVM_NONE)

        // J. FINAL TEST COMPLETION
        // ----------------------------------------------------

        `uvm_info(
            "TEST_PASS",
            $sformatf(
                {
                    "\n",
                    "========================================\n",
                    " INT8 SYSTOLIC ARRAY UVM TEST\n",
                    "========================================\n",
                    "Transactions executed : %0d\n",
                    "Transactions passed   : %0d\n",
                    "Output elements checked: %0d\n",
                    "Failed transactions   : %0d\n",
                    "Failed output elements: %0d\n",
                    "========================================\n",
                    " TEST PASSED\n",
                    "========================================"
                },
                expected_transactions,
                env.scoreboard.transactions_passed,
                env.scoreboard.elements_checked,
                env.scoreboard.transactions_failed,
                env.scoreboard.elements_failed
            ),
            UVM_NONE
        )

        phase.drop_objection(this);

    endtask

    // ========================================================
    // 6. CHECK PHASE
    // ========================================================

    function void check_phase(uvm_phase phase);

        super.check_phase(phase);

        if (env.scoreboard.transactions_checked
            != expected_transactions) begin

            `uvm_error(
                "FINAL_COUNT",
                "Final transaction count mismatch"
            )

        end

        if (env.scoreboard.transactions_failed != 0 ||
            env.scoreboard.elements_failed != 0 ||
            env.scoreboard.protocol_errors != 0) begin

            `uvm_error(
                "FINAL_FAILURE",
                "Verification failures detected"
            )

        end

    endfunction

    // ========================================================
    // 7. REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "FINAL_TEST_REPORT",
            $sformatf(
                {
                    "\n",
                    "========================================\n",
                    " FINAL UVM VERIFICATION SUMMARY\n",
                    "========================================\n",
                    "Directed tests        : %0d\n",
                    "Randomized tests      : %0d\n",
                    "Expected transactions : %0d\n",
                    "Transactions checked  : %0d\n",
                    "Transactions passed   : %0d\n",
                    "Transactions failed   : %0d\n",
                    "Elements checked      : %0d\n",
                    "Elements failed       : %0d\n",
                    "========================================"
                },
                NUM_DIRECTED,
                num_random,
                expected_transactions,
                env.scoreboard.transactions_checked,
                env.scoreboard.transactions_passed,
                env.scoreboard.transactions_failed,
                env.scoreboard.elements_checked,
                env.scoreboard.elements_failed
            ),
            UVM_NONE
        )

    endfunction

endclass

`endif
