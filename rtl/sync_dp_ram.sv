`timescale 1ns/1ps
// Portable one-read/one-write synchronous RAM. Storage and read data are not
// reset, allowing memory inference. Consumers must track validity separately.
// IMPLEMENTATION=0: one-edge read, same-address reads return the old word.
// IMPLEMENTATION=1: OpenRAM, response on the following edge; collisions illegal.
// The GEMM controller avoids same-address read/write for both backends.
module sync_dp_ram #(
    parameter int WIDTH=8, DEPTH=64, IMPLEMENTATION=0,
    parameter int ADDR_W=(DEPTH>1 ? $clog2(DEPTH) : 1)
) (
    input logic clk,
    input logic wr_en,
    input logic [ADDR_W-1:0] wr_addr,
    input logic [WIDTH-1:0] wr_data,
    input logic rd_en,
    input logic [ADDR_W-1:0] rd_addr,
    output logic [WIDTH-1:0] rd_data
);
    initial if(IMPLEMENTATION!=0 && IMPLEMENTATION!=1) $fatal(1,"Unknown RAM implementation");
    generate if(IMPLEMENTATION==0) begin: inferred
    logic [WIDTH-1:0] mem[0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr]<=wr_data;
        if (rd_en) rd_data<=mem[rd_addr];
    end
    end else begin: sky130
        sky130_dp_ram #(.WIDTH(WIDTH),.DEPTH(DEPTH),.ADDR_W(ADDR_W)) storage(.*);
    end endgenerate
endmodule
