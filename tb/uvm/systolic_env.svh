
`ifndef SYSTOLIC_ENV_SVH
`define SYSTOLIC_ENV_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM ENVIRONMENT
// ============================================================
//
// Responsibilities:
// 1. Create the UVM agent
// 2. Create the UVM scoreboard
// 3. Configure the virtual interface
// 4. Configure active/passive agent operation
// 5. Connect monitor analysis ports to scoreboard FIFOs
// 6. Check environment configuration
// 7. Generate an environment verification report
//
// ============================================================

class systolic_env extends uvm_env;

    `uvm_component_utils(systolic_env)

    // ========================================================
    // 1. ENVIRONMENT COMPONENTS
    // ========================================================

    systolic_agent agent;
    systolic_scoreboard scoreboard;


    // ========================================================
    // 2. VIRTUAL INTERFACE
    // ========================================================

    virtual systolic_if vif;


    // ========================================================
    // 3. ENVIRONMENT CONFIGURATION
    // ========================================================

    uvm_active_passive_enum agent_mode = UVM_ACTIVE;


    // ========================================================
    // 4. CONSTRUCTOR
    // ========================================================

    function new(
        string name = "systolic_env",
        uvm_component parent = null
    );

        super.new(name, parent);

    endfunction


    // ========================================================
    // 5. BUILD PHASE
    // ========================================================

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        `uvm_info(
            "ENV_BUILD",
            "Building INT8 systolic-array UVM environment",
            UVM_LOW
        )


        // ----------------------------------------------------
        // A. OBTAIN VIRTUAL INTERFACE
        // ----------------------------------------------------

        if (!uvm_config_db#(virtual systolic_if)::get(
            this,
            "",
            "vif",
            vif
        )) begin

            `uvm_fatal(
                "ENV_NO_VIF",
                "Environment could not obtain virtual interface"
            )

        end


        // ----------------------------------------------------
        // B. OBTAIN OPTIONAL AGENT CONFIGURATION
        // ----------------------------------------------------

        // Default configuration is UVM_ACTIVE.

        void'(
            uvm_config_db#(uvm_active_passive_enum)::get(
                this,
                "",
                "agent_mode",
                agent_mode
            )
        );


        // ----------------------------------------------------
        // C. CONFIGURE AGENT
        // ----------------------------------------------------

        uvm_config_db#(virtual systolic_if)::set(
            this,
            "agent",
            "vif",
            vif
        );

        uvm_config_db#(uvm_active_passive_enum)::set(
            this,
            "agent",
            "is_active",
            agent_mode
        );


        // ----------------------------------------------------
        // D. CREATE AGENT
        // ----------------------------------------------------

        agent = systolic_agent::type_id::create(
            "agent",
            this
        );


        // ----------------------------------------------------
        // E. CREATE SCOREBOARD
        // ----------------------------------------------------

        scoreboard = systolic_scoreboard::type_id::create(
            "scoreboard",
            this
        );


        `uvm_info(
            "ENV_BUILD",
            "UVM agent and scoreboard created",
            UVM_LOW
        )

    endfunction


    // ========================================================
    // 6. CONNECT PHASE
    // ========================================================

    function void connect_phase(uvm_phase phase);

        super.connect_phase(phase);


        // ----------------------------------------------------
        // A. CHECK COMPONENT HANDLES
        // ----------------------------------------------------

        if (agent == null ||
            agent.monitor == null ||
            scoreboard == null) begin

            `uvm_fatal(
                "ENV_CONNECT",
                "Required UVM components are missing"
            )

        end


        // ----------------------------------------------------
        // B. CONNECT REQUEST ANALYSIS PATH
        // ----------------------------------------------------

        // Monitor request port -> Scoreboard request FIFO

        agent.monitor.request_ap.connect(
            scoreboard.request_fifo.analysis_export
        );


        // ----------------------------------------------------
        // C. CONNECT RESPONSE ANALYSIS PATH
        // ----------------------------------------------------

        // Monitor response port -> Scoreboard response FIFO

        agent.monitor.response_ap.connect(
            scoreboard.response_fifo.analysis_export
        );


        `uvm_info(
            "ENV_CONNECT",
            "Monitor analysis ports connected to scoreboard",
            UVM_LOW
        )

    endfunction


    // ========================================================
    // 7. END OF ELABORATION PHASE
    // ========================================================

    function void end_of_elaboration_phase(
        uvm_phase phase
    );

        super.end_of_elaboration_phase(phase);

        `uvm_info(
            "ENV_CONFIG",
            $sformatf(
                "Environment initialized | Agent mode: %s",
                (agent_mode == UVM_ACTIVE)
                    ? "ACTIVE" : "PASSIVE"
            ),
            UVM_LOW
        )

    endfunction


    // ========================================================
    // 8. CHECK PHASE
    // ========================================================

    function void check_phase(uvm_phase phase);

        super.check_phase(phase);

        if (agent == null || scoreboard == null) begin

            `uvm_error(
                "ENV_CHECK",
                "Environment components are not initialized"
            )

        end

        if (agent != null && agent.monitor == null) begin

            `uvm_error(
                "ENV_CHECK",
                "UVM monitor is missing"
            )

        end

    endfunction


    // ========================================================
    // 9. REPORT PHASE
    // ========================================================

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info(
            "ENV_REPORT",
            $sformatf(
                {
                    "\n",
                    "========================================\n",
                    " INT8 SYSTOLIC ARRAY - UVM ENVIRONMENT\n",
                    "========================================\n",
                    "Agent mode             : %s\n",
                    "Transactions checked   : %0d\n",
                    "Transactions passed    : %0d\n",
                    "Transactions failed    : %0d\n",
                    "Output elements checked: %0d\n",
                    "========================================"
                },
                (agent_mode == UVM_ACTIVE)
                    ? "ACTIVE" : "PASSIVE",
                scoreboard.transactions_checked,
                scoreboard.transactions_passed,
                scoreboard.transactions_failed,
                scoreboard.elements_checked
            ),
            UVM_LOW
        )

    endfunction

endclass

`endif
