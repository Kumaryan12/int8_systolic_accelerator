`timescale 1ns/1ps
module memory_gemm #(
    parameter int M=3,K=5,N=7,TILE=4,DATA_W=8,TAG_W=8,SRAM_IMPL=0,
    parameter int OUT_W=19,INDEX_W=5
) (
    input wire clk,rst_n,load_valid,load_bank,load_last,result_ready,
    input wire signed [DATA_W-1:0] load_data,
    input wire [TAG_W-1:0] load_tag,
    output wire load_ready,load_error,result_valid,result_bank,result_last,busy,compute_done,
    output wire signed [OUT_W-1:0] result_data,
    output wire [TAG_W-1:0] result_tag,completed_tag,
    output wire [INDEX_W-1:0] result_index,
    output wire [1:0] bank_free
);
    initial if (M!=3 || K!=5 || N!=7 || TILE!=4 || DATA_W!=8 || TAG_W!=8 || OUT_W!=19 || INDEX_W!=5)
        $fatal(1,"Physical netlist adapter requires the default mapped configuration");
    memory_gemm_gate mapped(.*);
endmodule
