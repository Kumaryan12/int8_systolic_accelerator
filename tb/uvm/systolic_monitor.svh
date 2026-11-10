
`ifndef SYSTOLIC_MONITOR_SVH
`define SYSTOLIC_MONITOR_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM MONITOR
// ============================================================
//
// Responsibilities:
// 1. Observe DUT signals through virtual interface
// 2. Detect accepted matrix transactions
// 3. Capture input matrices A and B
// 4. Detect calculation completion
// 5. Capture output matrix C
// 6. Forward requests and responses to scoreboard
// 7. Handle reset-aborted transactions
//
// ============================================================

class systolic_monitor extends uvm_monitor;

    `uvm_component_utils(systolic_monitor)

    // ========================================================
    // 1. VIRTUAL INTERFACE
    // ========================================================

    virtual systolic_if vif;


    // ========================================================
    // 2. ANALYSIS PORTS
    // ========================================================

    // Sends accepted input transactions to scoreboard
    uvm_analysis_port #(systolic_transaction) request_ap;

    // Sends completed output transactions to scoreboard
    uvm_analysis_port #(systolic_transaction) response_ap;


    // ========================================================
    // 3. INTERNAL TRANSACTION STORAGE
    // ========================================================

    systolic_transaction active_req;

    int unsigned accepted_transactions = 0;
    int unsigned completed_transactions = 0;
    int unsigned aborted_transactions = 0;

    bit transaction_active = 0;


    // ========================================================
    // 4. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_monitor",
        uvm_component parent = null
    );

        super.new(name, parent);

        request_ap = new("request_ap", this);
        response_ap = new("response_ap", this);

    endfunction


    // ========================================================
    // 5. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // Obtain virtual interface from config database
        if (!uvm_config_db#(virtual systolic_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin

            `uvm_fatal(
                "NO_VIF",
                "Monitor could not obtain virtual interface"
            )

        end

    endfunction


    // ========================================================
    // 6. CAPTURE ACCEPTED REQUEST
    // ========================================================

    function void capture_request();

        systolic_transaction req;

        // Detect unexpected overlapping transaction
        if (transaction_active) begin

            `uvm_error(
                "OVERLAP",
                "New transaction accepted while previous job is active"
            )

            return;

        end

        req = systolic_transaction::type_id::create(
            $sformatf("request_%0d", accepted_transactions)
        );

        // Capture matrix operands
        req.a_matrix = vif.monitor_cb.a_matrix;
        req.b_matrix = vif.monitor_cb.b_matrix;

        req.c_matrix = '0;
        req.is_response = 0;

        // Store request for response correlation
        active_req = req;

        transaction_active = 1;

        accepted_transactions++;

        // Send request to scoreboard
        request_ap.write(req);

        `uvm_info(
            "MONITOR_REQ",
            $sformatf(
                "Accepted transaction %0d: A=%032h B=%032h",
                accepted_transactions,
                req.a_matrix,
                req.b_matrix
            ),
            UVM_HIGH
        )

    endfunction


    // ========================================================
    // 7. CAPTURE COMPLETED RESPONSE
    // ========================================================

    function void capture_response();

        systolic_transaction rsp;

        // Detect completion without a pending request
        if (!transaction_active || active_req == null) begin

            `uvm_error(
                "UNEXPECTED_DONE",
                "DUT asserted done without an active request"
            )

            return;

        end

        rsp = systolic_transaction::type_id::create(
            $sformatf("response_%0d", completed_transactions)
        );

        // Copy original request operands
        rsp.a_matrix = active_req.a_matrix;
        rsp.b_matrix = active_req.b_matrix;

        // Capture actual hardware output
        rsp.c_matrix = vif.monitor_cb.c_matrix;

        rsp.is_response = 1;

        completed_transactions++;

        // Send observed result to scoreboard
        response_ap.write(rsp);

        `uvm_info(
            "MONITOR_RSP",
            $sformatf(
                "Completed transaction %0d: C=%072h",
                completed_transactions,
                rsp.c_matrix
            ),
            UVM_HIGH
        )

        // Release active transaction
        transaction_active = 0;
        active_req = null;

    endfunction


    // ========================================================
    // 8. HANDLE RESET
    // ========================================================

    function void handle_reset();

        systolic_transaction aborted_rsp;

        if (transaction_active) begin

            aborted_transactions++;
            // An explicit terminal response prevents a stale request from
            // being compared with the first completed job after reset.
            aborted_rsp = systolic_transaction::type_id::create("reset_abort");
            aborted_rsp.a_matrix = active_req.a_matrix;
            aborted_rsp.b_matrix = active_req.b_matrix;
            aborted_rsp.is_response = 1;
            aborted_rsp.is_aborted = 1;
            response_ap.write(aborted_rsp);

            `uvm_info(
                "MONITOR_RESET",
                "Active transaction aborted by reset",
                UVM_MEDIUM
            )

        end

        transaction_active = 0;
        active_req = null;

    endfunction


    // ========================================================
    // 9. RUN PHASE
    // ========================================================

    task run_phase(uvm_phase phase);

        `uvm_info(
            "MONITOR",
            "Systolic monitor started",
            UVM_LOW
        )

        forever begin

            // Sample signals using monitor clocking block
            @(vif.monitor_cb);

            // ------------------------------------------------
            // A. RESET HANDLING
            // ------------------------------------------------

            if (vif.monitor_cb.rst_n !== 1'b1) begin

                handle_reset();

            end else begin

                // --------------------------------------------
                // B. CHECK FOR COMPLETED TRANSACTION
                // --------------------------------------------

                // done is a single-cycle completion pulse.
                // Capture response before a possible new launch.

                if (vif.monitor_cb.done === 1'b1) begin

                    if (vif.monitor_cb.busy !== 1'b0) begin

                        `uvm_error(
                            "PROTOCOL",
                            "busy and done asserted simultaneously"
                        )

                    end

                    capture_response();

                end


                // --------------------------------------------
                // C. CHECK FOR ACCEPTED NEW REQUEST
                // --------------------------------------------

                // DUT accepts start only when not busy.
                // A new start can coincide with the previous
                // transaction's completion pulse.

                if (vif.monitor_cb.start === 1'b1 &&
                    vif.monitor_cb.busy === 1'b0) begin

                    capture_request();

                end

            end

        end

    endtask


    // ========================================================
    // 10. CHECK PHASE
    // ========================================================

    function void check_phase(uvm_phase phase);

        super.check_phase(phase);

        // All normal transactions must finish
        if (transaction_active) begin

            `uvm_error(
                "PENDING_TRANSACTION",
                "Simulation ended with an unfinished transaction"
            )

        end

        if (accepted_transactions !=
            completed_transactions + aborted_transactions) begin

            `uvm_error(
                "TRANSACTION_COUNT",
                $sformatf(
                    "Accepted=%0d Completed=%0d Aborted=%0d",
                    accepted_transactions,
                    completed_transactions,
                    aborted_transactions
                )
            )

        end

    endfunction


    // ========================================================
    // 11. REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "MONITOR_REPORT",
            $sformatf(
                {
                    "Accepted transactions : %0d\n",
                    "Completed transactions: %0d\n",
                    "Aborted transactions  : %0d"
                },
                accepted_transactions,
                completed_transactions,
                aborted_transactions
            ),
            UVM_LOW
        )

    endfunction

endclass

`endif
