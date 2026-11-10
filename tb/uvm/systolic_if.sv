
`timescale 1ns/1ps

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM VERIFICATION INTERFACE
// ============================================================

interface systolic_if #(
    parameter integer N = 4,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 2*DATA_W + $clog2(N)
)(
    input logic clk
);

    // ========================================================
    // 1. CONTROL SIGNALS
    // ========================================================

    logic rst_n = 1'b0;
    logic start = 1'b0;

    logic busy;
    logic done;


    // ========================================================
    // 2. MATRIX DATA SIGNALS
    // ========================================================

    logic [N*N*DATA_W-1:0] a_matrix = '0;
    logic [N*N*DATA_W-1:0] b_matrix = '0;

    logic [N*N*ACC_W-1:0] c_matrix;


    // ========================================================
    // 3. DRIVER CLOCKING BLOCK
    // ========================================================

    // Drive inputs on the falling edge.
    // DUT captures them on the following rising edge.

    clocking driver_cb @(negedge clk);

        default input #1step output #0;

        output rst_n;
        output start;
        output a_matrix;
        output b_matrix;

        input busy;
        input done;

    endclocking


    // ========================================================
    // 4. MONITOR CLOCKING BLOCK
    // ========================================================

    // Sample signals immediately before the rising edge.
    // This gives a consistent pre-edge view of DUT signals.

    clocking monitor_cb @(posedge clk);

        default input #1step;

        input rst_n;
        input start;

        input a_matrix;
        input b_matrix;

        input busy;
        input done;
        input c_matrix;

    endclocking


    // ========================================================
    // 5. DRIVER MODPORT
    // ========================================================

    modport DRIVER (
        clocking driver_cb,
        input clk
    );


    // ========================================================
    // 6. MONITOR MODPORT
    // ========================================================

    modport MONITOR (
        clocking monitor_cb,
        input clk
    );


    // ========================================================
    // 7. PASSIVE OBSERVATION MODPORT
    // ========================================================

    modport PASSIVE (
        input clk,
        input rst_n,
        input start,
        input busy,
        input done,
        input a_matrix,
        input b_matrix,
        input c_matrix
    );


endinterface
