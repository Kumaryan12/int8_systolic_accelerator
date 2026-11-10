
`ifndef SYSTOLIC_AGENT_SVH
`define SYSTOLIC_AGENT_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM AGENT
// ============================================================
//
// Responsibilities:
// 1. Create UVM driver
// 2. Create UVM monitor
// 3. Create UVM sequencer
// 4. Connect driver to sequencer
// 5. Configure virtual interfaces
// 6. Support active and passive verification modes
//
// ============================================================

class systolic_agent extends uvm_agent;

    `uvm_component_utils(systolic_agent)

    // ========================================================
    // 1. UVM COMPONENTS
    // ========================================================

    systolic_driver driver;

    systolic_monitor monitor;

    uvm_sequencer #(systolic_transaction) sequencer;


    // ========================================================
    // 2. VIRTUAL INTERFACE
    // ========================================================

    virtual systolic_if vif;


    // ========================================================
    // 3. AGENT CONFIGURATION
    // ========================================================

    // Active mode:
    // Driver + Sequencer + Monitor
    //
    // Passive mode:
    // Monitor only

    uvm_active_passive_enum is_active = UVM_ACTIVE;


    // ========================================================
    // 4. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_agent",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    // ========================================================
    // 5. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // ----------------------------------------------------
        // A. GET AGENT CONFIGURATION
        // ----------------------------------------------------

        // Defaults to UVM_ACTIVE if not configured.

        void'(
            uvm_config_db#(uvm_active_passive_enum)::get(
                this,
                "",
                "is_active",
                is_active
            )
        );


        // ----------------------------------------------------
        // B. GET VIRTUAL INTERFACE
        // ----------------------------------------------------

        if (!uvm_config_db#(virtual systolic_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin

            `uvm_fatal(
                "AGENT_NO_VIF",
                "Agent could not obtain virtual interface"
            )

        end


        // ----------------------------------------------------
        // C. CREATE MONITOR
        // ----------------------------------------------------

        // Monitor is created in both active and passive modes.

        uvm_config_db#(virtual systolic_if)::set(
            this,
            "monitor",
            "vif",
            vif
        );

        monitor = systolic_monitor::type_id::create(
            "monitor",
            this
        );


        // ----------------------------------------------------
        // D. CREATE DRIVER AND SEQUENCER
        // ----------------------------------------------------

        if (is_active == UVM_ACTIVE) begin

            // Configure driver virtual interface
            uvm_config_db#(virtual systolic_if)::set(
                this,
                "driver",
                "vif",
                vif
            );

            // Create driver
            driver = systolic_driver::type_id::create(
                "driver",
                this
            );

            // Create sequencer
            sequencer =
                uvm_sequencer#(systolic_transaction)
                ::type_id::create(
                    "sequencer",
                    this
                );

            `uvm_info(
                "AGENT_BUILD",
                "Active agent components created",
                UVM_LOW
            )

        end else begin

            `uvm_info(
                "AGENT_BUILD",
                "Passive agent created: monitor only",
                UVM_LOW
            )

        end

    endfunction


    // ========================================================
    // 6. CONNECT PHASE
    // ========================================================

    function void connect_phase(uvm_phase phase);

        super.connect_phase(phase);

        // ----------------------------------------------------
        // CONNECT DRIVER TO SEQUENCER
        // ----------------------------------------------------

        if (is_active == UVM_ACTIVE) begin

            if (driver == null || sequencer == null) begin

                `uvm_fatal(
                    "AGENT_CONNECT",
                    "Driver or sequencer is null"
                )

            end

            driver.seq_item_port.connect(
                sequencer.seq_item_export
            );

            `uvm_info(
                "AGENT_CONNECT",
                "Driver connected to sequencer",
                UVM_LOW
            )

        end

        // The monitor's analysis ports will be connected
        // to scoreboard FIFOs in the UVM environment.

    endfunction


    // ========================================================
    // 7. END OF ELABORATION PHASE
    // ========================================================

    function void end_of_elaboration_phase(
        uvm_phase phase
    );

        super.end_of_elaboration_phase(phase);

        if (is_active == UVM_ACTIVE) begin

            `uvm_info(
                "AGENT_CONFIG",
                "Agent mode: ACTIVE",
                UVM_LOW
            )

        end else begin

            `uvm_info(
                "AGENT_CONFIG",
                "Agent mode: PASSIVE",
                UVM_LOW
            )

        end

    endfunction


    // ========================================================
    // 8. REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "AGENT_REPORT",
            $sformatf(
                {
                    "\n",
                    "====================================\n",
                    " SYSTOLIC ARRAY UVM AGENT REPORT\n",
                    "====================================\n",
                    "Agent mode       : %s\n",
                    "Monitor accepted : %0d\n",
                    "Monitor completed: %0d\n",
                    "Monitor aborted  : %0d\n",
                    "===================================="
                },
                (is_active == UVM_ACTIVE)
                    ? "ACTIVE" : "PASSIVE",
                monitor.accepted_transactions,
                monitor.completed_transactions,
                monitor.aborted_transactions
            ),
            UVM_LOW
        )

    endfunction

endclass

`endif
