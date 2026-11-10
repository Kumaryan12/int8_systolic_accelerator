`timescale 1ns/1ps
// Reuse parameterized testbenches with a fixed 4x4 technology-mapped netlist.
module systolic_array #(
    parameter int N=4, DATA_W=8, ACC_W=18
) (
    input wire clk, rst_n, start,
    input wire [N*N*DATA_W-1:0] a_matrix, b_matrix,
    output wire busy, done,
    output wire [N*N*ACC_W-1:0] c_matrix
);
    initial if (N != 4 || DATA_W != 8 || ACC_W != 18)
        $fatal(1, "Gate adapter only supports the mapped N=4 INT8/INT18 configuration");
    systolic_array_gate mapped (.*);
endmodule
