`timescale 1ns/1ps
module tb_sva_top;
    tb_advanced testbench();
    systolic_sva properties (
        .clk(testbench.clk), .rst_n(testbench.rst_n), .start(testbench.start),
        .busy(testbench.busy), .done(testbench.done), .c_matrix(testbench.c_matrix)
    );
endmodule
