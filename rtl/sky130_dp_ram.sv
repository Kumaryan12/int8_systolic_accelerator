`timescale 1ns/1ps
// Banked OpenRAM 1RW1R backend, 32 bits x 256 words per macro. A request
// sampled on edge t produces a held response just after edge t+1. The
// falling-edge macro output is captured before its next-cycle invalidation.
// No reset on data storage or this response; the owner tracks validity.
module sky130_dp_ram #(
    parameter integer WIDTH=8, DEPTH=64,
    parameter integer ADDR_W=(DEPTH>1 ? $clog2(DEPTH) : 1)
)(
    input wire clk,wr_en,
    input wire [ADDR_W-1:0] wr_addr,
    input wire [WIDTH-1:0] wr_data,
    input wire rd_en,
    input wire [ADDR_W-1:0] rd_addr,
    output reg [WIDTH-1:0] rd_data
);
    localparam integer BANKS=(DEPTH+255)/256;
    localparam integer BANK_W=(BANKS>1 ? $clog2(BANKS) : 1);
    wire [31:0] macro_read[0:BANKS-1];
    wire [31:0] write_word={{(32-WIDTH){1'b0}},wr_data};
    reg read_pending;
    reg [BANK_W-1:0] read_bank;
    initial begin
        if(WIDTH<1 || WIDTH>32 || DEPTH<1 || ADDR_W<(DEPTH>1 ? $clog2(DEPTH) : 1))
            $fatal(1,"Unsupported SRAM geometry");
    end
    for(genvar b=0;b<BANKS;b=b+1) begin: banks
        wire [31:0] bank_read;
        wire write_csb=!(wr_en && int'(wr_addr)/256==b);
        wire read_csb=!(rd_en && int'(rd_addr)/256==b);
        wire [7:0] write_address=8'(wr_addr), read_address=8'(rd_addr);
        assign macro_read[b]=bank_read;
        sky130_sram_1kbyte_1rw1r_32x256_8
`ifndef SYNTHESIS
        #(.VERBOSE(0))
`endif
        macro (
            .clk0(clk),.csb0(write_csb),.web0(1'b0),
            .wmask0(4'b1111),.addr0(write_address),.din0(write_word),.dout0(),
            .clk1(clk),.csb1(read_csb),
            .addr1(read_address),.dout1(bank_read)
        );
    end
    always @(posedge clk) begin
        read_pending<=rd_en;
        if(rd_en) read_bank<=BANK_W'(int'(rd_addr)/256);
        if(read_pending) rd_data<=macro_read[read_bank][WIDTH-1:0];
    end
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if(wr_en && int'(wr_addr)>=DEPTH) $fatal(1,"SRAM write outside logical depth");
        if(rd_en && int'(rd_addr)>=DEPTH) $fatal(1,"SRAM read outside logical depth");
        if(wr_en && rd_en && wr_addr==rd_addr)
            $fatal(1,"OpenRAM same-address read/write is unsupported");
    end
`endif
endmodule
