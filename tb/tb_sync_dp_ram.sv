`timescale 1ns/1ps
module tb_sync_dp_ram;
    reg clk=0,wr_en=0,rd_en=0;
    reg [2:0] wr_addr=0,rd_addr=0;
    reg [7:0] wr_data=0;
    wire [7:0] rd_data;
    always #5 clk=~clk;
    sync_dp_ram #(.WIDTH(8),.DEPTH(7)) dut(.*);
    initial begin
        for (integer i=0;i<7;i++) begin
            @(negedge clk); wr_en=1; wr_addr=3'(i); wr_data=8'(17+i);
        end
        @(negedge clk); wr_en=0;
        for (integer i=0;i<7;i++) begin
            rd_addr=3'(i); rd_en=1;
            @(posedge clk); #1;
            if (rd_data !== 8'(17+i)) $fatal(1,"Synchronous RAM read failed");
            @(negedge clk);
        end
        rd_en=0; rd_addr=0; #1;
        if (rd_data!==8'd23) $fatal(1,"RAM output changed with read disabled");
        @(posedge clk); #1;
        if (rd_data!==8'd23) $fatal(1,"RAM output did not hold");
        @(negedge clk); wr_en=1; wr_addr=0; wr_data=99; rd_en=1; rd_addr=0;
        @(posedge clk); #1;
        if (rd_data!==8'd17) $fatal(1,"RAM read/write collision is not read-first");
        @(negedge clk); wr_en=0;
        @(posedge clk); #1;
        if (rd_data!==8'd99) $fatal(1,"RAM updated word missing");
        $display("PASS: Synchronous RAM latency, hold and read-first checks");
        $finish;
    end
endmodule
