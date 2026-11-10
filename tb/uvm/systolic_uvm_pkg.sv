
`timescale 1ns/1ps

`ifndef SYSTOLIC_UVM_PKG_SV
`define SYSTOLIC_UVM_PKG_SV

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM VERIFICATION PACKAGE
// ============================================================
//
// Design:
//   4x4 INT8 Systolic Array Accelerator
//
// Verification methodology:
//   Universal Verification Methodology (UVM)
//
// Package includes:
//   1. Transaction
//   2. Sequence
//   3. Driver
//   4. Monitor
//   5. Scoreboard
//   6. Agent
//   7. Environment
//   8. Test
//
// ============================================================

package systolic_uvm_pkg;

    // ========================================================
    // 1. IMPORT UVM LIBRARY
    // ========================================================

    import uvm_pkg::*;

    // ========================================================
    // 2. INCLUDE UVM MACROS
    // ========================================================

    `include "uvm_macros.svh"


    // ========================================================
    // 3. TRANSACTION CLASS
    // ========================================================

    `include "systolic_transaction.svh"


    // ========================================================
    // 4. TEST SEQUENCE
    // ========================================================

    `include "systolic_sequence.svh"


    // ========================================================
    // 5. UVM DRIVER
    // ========================================================

    `include "systolic_driver.svh"


    // ========================================================
    // 6. UVM MONITOR
    // ========================================================

    `include "systolic_monitor.svh"


    // ========================================================
    // 7. UVM SCOREBOARD
    // ========================================================

    `include "systolic_scoreboard.svh"


    // ========================================================
    // 8. UVM AGENT
    // ========================================================

    `include "systolic_agent.svh"


    // ========================================================
    // 9. UVM ENVIRONMENT
    // ========================================================

    `include "systolic_env.svh"


    // ========================================================
    // 10. UVM TEST
    // ========================================================

    `include "systolic_test.svh"

endpackage

`endif
