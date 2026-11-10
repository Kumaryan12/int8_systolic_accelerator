
`ifndef SYSTOLIC_SCOREBOARD_SVH
`define SYSTOLIC_SCOREBOARD_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM SCOREBOARD
// ============================================================
//
// Responsibilities:
// 1. Receive accepted requests from the UVM monitor
// 2. Receive completed responses from the UVM monitor
// 3. Calculate expected matrix multiplication results
// 4. Compare all 16 RTL outputs against the golden model
// 5. Detect unexpected or mismatched transactions
// 6. Maintain pass/fail statistics
// 7. Generate a final verification report
//
// Configuration:
// Matrix size       : 4 x 4
// Input precision   : Signed INT8
// Output precision  : Signed INT18
//
// ============================================================

class systolic_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(systolic_scoreboard)

    // ========================================================
    // 1. ANALYSIS FIFOS
    // ========================================================

    // Receives requests from monitor.request_ap
    uvm_tlm_analysis_fifo #(systolic_transaction)
        request_fifo;

    // Receives responses from monitor.response_ap
    uvm_tlm_analysis_fifo #(systolic_transaction)
        response_fifo;


    // ========================================================
    // 2. SCOREBOARD CONFIGURATION
    // ========================================================

    localparam int N = 4;
    localparam int ACC_W = 18;

    // ========================================================
    // 3. VERIFICATION COUNTERS
    // ========================================================

    int unsigned requests_received = 0;
    int unsigned responses_received = 0;

    int unsigned transactions_checked = 0;
    int unsigned transactions_passed = 0;
    int unsigned transactions_failed = 0;

    int unsigned elements_checked = 0;
    int unsigned elements_passed = 0;
    int unsigned elements_failed = 0;

    int unsigned protocol_errors = 0;
    int unsigned transactions_aborted = 0;


    // ========================================================
    // 4. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_scoreboard",
        uvm_component parent = null
    );

        super.new(name, parent);

        request_fifo = new("request_fifo", this);
        response_fifo = new("response_fifo", this);

    endfunction


    // ========================================================
    // 5. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        `uvm_info(
            "SCOREBOARD",
            "INT8 systolic-array scoreboard initialized",
            UVM_LOW
        )

    endfunction


    // ========================================================
    // 6. COMPARE ONE COMPLETE TRANSACTION
    // ========================================================

    function void compare_transaction(
        systolic_transaction req,
        systolic_transaction rsp
    );

        bit [287:0] expected_matrix;

        logic signed [ACC_W-1:0] expected_value;
        logic signed [ACC_W-1:0] actual_value;

        bit transaction_failed;

        transaction_failed = 0;

        transactions_checked++;


        // ----------------------------------------------------
        // A. CHECK REQUEST/RESPONSE TYPE
        // ----------------------------------------------------

        if (req.is_response !== 1'b0) begin

            protocol_errors++;
            transaction_failed = 1;

            `uvm_error(
                "SB_REQ_TYPE",
                "Request transaction has incorrect response flag"
            )

        end

        if (rsp.is_response !== 1'b1) begin

            protocol_errors++;
            transaction_failed = 1;

            `uvm_error(
                "SB_RSP_TYPE",
                "Response transaction has incorrect response flag"
            )

        end


        // ----------------------------------------------------
        // B. VERIFY TRANSACTION CORRELATION
        // ----------------------------------------------------

        // The DUT processes one transaction at a time.
        // Requests and responses must therefore remain
        // in the same order.

        if (req.a_matrix !== rsp.a_matrix ||
            req.b_matrix !== rsp.b_matrix) begin

            protocol_errors++;
            transaction_failed = 1;

            `uvm_error(
                "SB_TRANSACTION",
                "Request/response operands do not match"
            )

        end


        // ----------------------------------------------------
        // C. CALCULATE GOLDEN REFERENCE RESULT
        // ----------------------------------------------------

        // Calls the independent mathematical model
        // defined in systolic_transaction.svh.

        expected_matrix = req.expected_matrix();


        // ----------------------------------------------------
        // D. COMPARE ALL 16 OUTPUT ELEMENTS
        // ----------------------------------------------------

        for (int r = 0; r < N; r++) begin

            for (int c = 0; c < N; c++) begin

                expected_value = expected_matrix[
                    ACC_W*(r*N+c) +: ACC_W
                ];

                actual_value = rsp.c_matrix[
                    ACC_W*(r*N+c) +: ACC_W
                ];

                elements_checked++;

                // Case inequality also catches X and Z.
                if (actual_value !== expected_value) begin

                    elements_failed++;
                    transaction_failed = 1;

                    `uvm_error(
                        "SB_DATA_MISMATCH",
                        $sformatf(
                            {
                                "Transaction %0d mismatch\n",
                                "Element C[%0d][%0d]\n",
                                "Expected = %0d\n",
                                "Actual   = %0d"
                            },
                            transactions_checked,
                            r,
                            c,
                            $signed(expected_value),
                            $signed(actual_value)
                        )
                    )

                end else begin

                    elements_passed++;

                end

            end

        end


        // ----------------------------------------------------
        // E. UPDATE TRANSACTION STATISTICS
        // ----------------------------------------------------

        if (transaction_failed) begin

            transactions_failed++;

            `uvm_error(
                "SB_FAIL",
                $sformatf(
                    "Matrix transaction %0d FAILED",
                    transactions_checked
                )
            )

        end else begin

            transactions_passed++;

            `uvm_info(
                "SB_PASS",
                $sformatf(
                    "Matrix transaction %0d PASSED (16/16 elements)",
                    transactions_checked
                ),
                UVM_MEDIUM
            )

        end

    endfunction


    // ========================================================
    // 7. RUN PHASE
    // ========================================================

    task run_phase(uvm_phase phase);

        systolic_transaction req;
        systolic_transaction rsp;

        `uvm_info(
            "SCOREBOARD",
            "Scoreboard comparison process started",
            UVM_LOW
        )

        forever begin

            // ------------------------------------------------
            // A. WAIT FOR AN ACCEPTED REQUEST
            // ------------------------------------------------

            request_fifo.get(req);

            requests_received++;


            // ------------------------------------------------
            // B. WAIT FOR CORRESPONDING RESPONSE
            // ------------------------------------------------

            response_fifo.get(rsp);

            responses_received++;


            // ------------------------------------------------
            // C. CHECK FOR NULL TRANSACTIONS
            // ------------------------------------------------

            if (req == null || rsp == null) begin

                protocol_errors++;

                `uvm_error(
                    "SB_NULL",
                    "Null transaction received"
                )

            end else if (rsp.is_aborted) begin
                if (req.a_matrix !== rsp.a_matrix || req.b_matrix !== rsp.b_matrix || !rsp.is_response) begin
                    protocol_errors++;
                    `uvm_error("SB_ABORT", "Reset-aborted response does not match pending request")
                end
                transactions_aborted++;
            end else begin

                // --------------------------------------------
                // D. COMPARE HARDWARE WITH GOLDEN MODEL
                // --------------------------------------------

                compare_transaction(req, rsp);

            end

        end

    endtask


    // ========================================================
    // 8. CHECK PHASE
    // ========================================================

    function void check_phase(uvm_phase phase);

        super.check_phase(phase);


        // ----------------------------------------------------
        // A. VERIFY THAT TRANSACTIONS WERE EXECUTED
        // ----------------------------------------------------

        if (transactions_checked == 0) begin

            `uvm_error(
                "SB_NO_TESTS",
                "No transactions were checked by scoreboard"
            )

        end


        // ----------------------------------------------------
        // B. CHECK REQUEST/RESPONSE COUNTS
        // ----------------------------------------------------

        if (requests_received != responses_received) begin

            `uvm_error(
                "SB_COUNT",
                $sformatf(
                    "Request count=%0d Response count=%0d",
                    requests_received,
                    responses_received
                )
            )

        end

        if (requests_received != transactions_checked + transactions_aborted)
            `uvm_error("SB_TERMINAL_COUNT", "Not every accepted request completed or aborted")


        // ----------------------------------------------------
        // C. CHECK FOR PENDING FIFO TRANSACTIONS
        // ----------------------------------------------------

        if (request_fifo.used() != 0) begin

            `uvm_error(
                "SB_PENDING_REQ",
                $sformatf(
                    "%0d unprocessed requests remain",
                    request_fifo.used()
                )
            )

        end

        if (response_fifo.used() != 0) begin

            `uvm_error(
                "SB_PENDING_RSP",
                $sformatf(
                    "%0d unprocessed responses remain",
                    response_fifo.used()
                )
            )

        end


        // ----------------------------------------------------
        // D. VERIFY ALL CHECKED TRANSACTIONS PASSED
        // ----------------------------------------------------

        if (transactions_failed != 0 ||
            elements_failed != 0 ||
            protocol_errors != 0) begin

            `uvm_error(
                "SB_CHECK_FAIL",
                "Scoreboard detected verification failures"
            )

        end


        // ----------------------------------------------------
        // E. VERIFY INTERNAL COUNTER CONSISTENCY
        // ----------------------------------------------------

        if (transactions_checked !=
            transactions_passed + transactions_failed) begin

            `uvm_error(
                "SB_COUNTER",
                "Transaction statistics are inconsistent"
            )

        end

        if (elements_checked !=
            elements_passed + elements_failed) begin

            `uvm_error(
                "SB_ELEMENT_COUNTER",
                "Element statistics are inconsistent"
            )

        end

        if (elements_checked != transactions_checked*N*N) begin

            `uvm_error(
                "SB_ELEMENT_COUNT",
                "Not all 16 output elements were checked"
            )

        end

    endfunction


    // ========================================================
    // 9. FINAL REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "SCOREBOARD_REPORT",
            $sformatf(
                {
                    "\n",
                    "========================================\n",
                    " INT8 SYSTOLIC ARRAY - UVM SCOREBOARD\n",
                    "========================================\n",
                    "Requests received    : %0d\n",
                    "Responses received   : %0d\n",
                    "Transactions checked : %0d\n",
                    "Transactions passed  : %0d\n",
                    "Transactions failed  : %0d\n",
                    "----------------------------------------\n",
                    "Elements checked     : %0d\n",
                    "Elements passed      : %0d\n",
                    "Elements failed      : %0d\n",
                    "Protocol errors      : %0d\n",
                    "========================================"
                },
                requests_received,
                responses_received,
                transactions_checked,
                transactions_passed,
                transactions_failed,
                elements_checked,
                elements_passed,
                elements_failed,
                protocol_errors
            ),
            UVM_NONE
        )

    endfunction

endclass

`endif
