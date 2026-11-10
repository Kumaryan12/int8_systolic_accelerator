
`timescale 1ns/1ps

module tb_uvm_top;

    import uvm_pkg::*;
    import systolic_uvm_pkg::*;

    // ========================================================
    // 1. HARDWARE PARAMETERS
    // ========================================================

    localparam int N = 4;
    localparam int DATA_W = 8;
    localparam int ACC_W = 18;

    // ========================================================
    // 2. CLOCK GENERATION
    // ========================================================

    logic clk = 1'b0;

    always #5 clk = ~clk;

    // ========================================================
    // 3. SYSTEMVERILOG INTERFACE
    // ========================================================

    // IMPORTANT:
    // Use the default interface specialization so it
    // matches "virtual systolic_if" in all UVM classes.
    //
    // Default parameters:
    // N = 4, DATA_W = 8, ACC_W = 18

    systolic_if dut_if (
        .clk(clk)
    );

    // ========================================================
    // 4. DEVICE UNDER TEST
    // ========================================================

    systolic_array #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(dut_if.rst_n),
        .start(dut_if.start),
        .a_matrix(dut_if.a_matrix),
        .b_matrix(dut_if.b_matrix),
        .busy(dut_if.busy),
        .done(dut_if.done),
        .c_matrix(dut_if.c_matrix)
    );

    // ========================================================
    // 5. UVM CONFIGURATION
    // ========================================================

    systolic_sva properties (
        .clk(clk), .rst_n(dut_if.rst_n), .start(dut_if.start),
        .busy(dut_if.busy), .done(dut_if.done), .c_matrix(dut_if.c_matrix)
    );

    initial begin

        $display("");
        $display("========================================");
        $display(" INT8 SYSTOLIC ARRAY - UVM SIMULATION");
        $display("========================================");
        $display("Array size       : %0d x %0d", N, N);
        $display("Input width      : %0d bits", DATA_W);
        $display("Accumulator width: %0d bits", ACC_W);
        $display("MAC units        : %0d", N*N);
        $display("========================================");

        // Set the virtual interface for UVM environment

        uvm_config_db#(virtual systolic_if)::set(
            null,
            "uvm_test_top.env",
            "vif",
            dut_if
        );

        // Launch UVM test

        run_test("systolic_test");

    end

    // ========================================================
    // 6. GLOBAL TIMEOUT
    // ========================================================

    initial begin

        #200_000;

        $fatal(
            1,
            "GLOBAL TIMEOUT: Simulation exceeded 200 us"
        );

    end

endmodule
