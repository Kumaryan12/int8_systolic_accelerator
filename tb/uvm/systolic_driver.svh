
`ifndef SYSTOLIC_DRIVER_SVH
`define SYSTOLIC_DRIVER_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM DRIVER
// ============================================================
//
// Responsibilities:
// 1. Obtain transactions from the UVM sequencer
// 2. Initialize and reset the DUT
// 3. Wait until the accelerator is idle
// 4. Drive input matrices A and B
// 5. Generate the start pulse
// 6. Wait for the computation to finish
// 7. Detect protocol errors and timeouts
//
// ============================================================

class systolic_driver extends
    uvm_driver #(systolic_transaction);

    `uvm_component_utils(systolic_driver)

    // ========================================================
    // 1. VIRTUAL INTERFACE
    // ========================================================

    virtual systolic_if vif;

    // Hardware configuration: 4x4 systolic array
    localparam int N = 4;
    localparam int COMPUTE_CYCLES = 3*N - 2;
    localparam int MAX_WAIT_CYCLES = COMPUTE_CYCLES + 4;

    // Driver statistics
    int unsigned transactions_driven = 0;
    int unsigned completed_transactions = 0;


    // ========================================================
    // 2. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_driver",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    // ========================================================
    // 3. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // Obtain interface from UVM configuration database
        if (!uvm_config_db#(virtual systolic_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin

            `uvm_fatal(
                "NO_VIF",
                "Driver could not obtain virtual interface"
            )

        end

    endfunction


    // ========================================================
    // 4. RESET TASK
    // ========================================================

    task reset_dut();

        `uvm_info(
            "DRIVER",
            "Applying initial DUT reset",
            UVM_LOW
        )

        // Apply reset on falling clock edge
        @(vif.driver_cb);

        vif.driver_cb.rst_n   <= 1'b0;
        vif.driver_cb.start   <= 1'b0;
        vif.driver_cb.a_matrix <= '0;
        vif.driver_cb.b_matrix <= '0;

        // Hold reset for three clock cycles
        repeat (3) @(vif.driver_cb);

        // Release reset
        vif.driver_cb.rst_n <= 1'b1;

        // Allow reset release to be observed
        @(vif.driver_cb);

        if (vif.driver_cb.busy !== 1'b0 ||
            vif.driver_cb.done !== 1'b0) begin

            `uvm_fatal(
                "RESET_FAIL",
                "DUT not idle after reset"
            )

        end

        `uvm_info(
            "DRIVER",
            "DUT reset completed",
            UVM_LOW
        )

    endtask


    // ========================================================
    // 5. DRIVE ONE MATRIX MULTIPLICATION TRANSACTION
    // ========================================================

    task drive_transaction(systolic_transaction tr);

        bit completed;

        completed = 0;

        // ----------------------------------------------------
        // A. WAIT FOR DUT TO BECOME IDLE
        // ----------------------------------------------------

        while (vif.driver_cb.busy !== 1'b0) begin

            @(vif.driver_cb);

        end

        // ----------------------------------------------------
        // B. DRIVE INPUT MATRICES
        // ----------------------------------------------------

        vif.driver_cb.a_matrix <= tr.a_matrix;
        vif.driver_cb.b_matrix <= tr.b_matrix;

        // Assert start for one clock cycle
        vif.driver_cb.start <= 1'b1;

        transactions_driven++;

        `uvm_info(
            "DRIVER",
            $sformatf(
                "Launching transaction %0d",
                transactions_driven
            ),
            UVM_MEDIUM
        )

        // ----------------------------------------------------
        // C. CHECK TRANSACTION ACCEPTANCE
        // ----------------------------------------------------

        // Next falling edge occurs after the DUT
        // has sampled start on a rising edge.

        @(vif.driver_cb);

        vif.driver_cb.start <= 1'b0;

        if (vif.driver_cb.busy !== 1'b1 ||
            vif.driver_cb.done !== 1'b0) begin

            `uvm_fatal(
                "START_FAIL",
                "DUT did not accept the transaction"
            )

        end

        // ----------------------------------------------------
        // D. WAIT FOR COMPUTATION COMPLETION
        // ----------------------------------------------------

        for (int cycle = 0;
             cycle < MAX_WAIT_CYCLES;
             cycle++) begin

            @(vif.driver_cb);

            // Check whether computation has finished
            if (vif.driver_cb.done === 1'b1) begin

                completed = 1;

                // DUT should be idle when done is asserted
                if (vif.driver_cb.busy !== 1'b0) begin

                    `uvm_fatal(
                        "PROTOCOL_FAIL",
                        "busy and done asserted together"
                    )

                end

                completed_transactions++;

                `uvm_info(
                    "DRIVER",
                    $sformatf(
                        "Transaction %0d completed",
                        completed_transactions
                    ),
                    UVM_MEDIUM
                )

                break;

            end

        end

        // ----------------------------------------------------
        // E. TIMEOUT DETECTION
        // ----------------------------------------------------

        if (!completed) begin

            `uvm_fatal(
                "TIMEOUT",
                $sformatf(
                    "DUT did not complete within %0d cycles",
                    MAX_WAIT_CYCLES
                )
            )

        end

        // ----------------------------------------------------
        // F. PREPARE FOR NEXT TRANSACTION
        // ----------------------------------------------------

        // Input matrices remain stable until the next job.
        // The DUT output will be captured by the UVM monitor.
        //
        // The driver does not calculate expected results.
        // That responsibility belongs to the scoreboard.

    endtask


    // ========================================================
    // 6. RUN PHASE
    // ========================================================

    task run_phase(uvm_phase phase);

        systolic_transaction tr;

        // Apply initial reset
        reset_dut();

        // Continuously process transactions
        forever begin

            // Receive next transaction from sequencer
            seq_item_port.get_next_item(tr);

            // Drive transaction to hardware
            drive_transaction(tr);

            // Inform sequencer that item is finished
            seq_item_port.item_done();

        end

    endtask


    // ========================================================
    // 7. REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "DRIVER_REPORT",
            $sformatf(
                "Transactions driven: %0d | Completed: %0d",
                transactions_driven,
                completed_transactions
            ),
            UVM_LOW
        )

    endfunction

endclass

`endif
