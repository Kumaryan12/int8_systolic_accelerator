`timescale 1ns/1ps
module tb_sky130_dp_ram;
    reg clk=0,wr_en=0,rd_en=0;
    reg [9:0] wr_addr=0,rd_addr=0;
    reg [18:0] wr_data=0;
    wire [18:0] rd_data;
    integer addresses[0:7];
    reg [18:0] held;
    sky130_dp_ram #(.WIDTH(19),.DEPTH(513)) dut(.*);
    always #5 clk=~clk;
    function automatic [18:0] pattern(input integer addr);
        pattern=19'(addr*131+4127);
    endfunction
    initial begin
        addresses[0]=0; addresses[1]=255; addresses[2]=256; addresses[3]=511;
        addresses[4]=512; addresses[5]=1; addresses[6]=257; addresses[7]=254;
        if($test$plusargs("COLLIDE")) begin
            @(negedge clk); wr_en=1; rd_en=1;
            repeat(2) @(posedge clk); $fatal(1,"Expected collision rejection");
        end
        if($test$plusargs("BAD_READ")) begin
            @(negedge clk); rd_en=1; rd_addr=513;
            repeat(2) @(posedge clk); $fatal(1,"Expected address rejection");
        end
        for(integer i=0;i<8;i=i+1) begin
            @(negedge clk);wr_en=1;wr_addr=10'(addresses[i]);wr_data=pattern(addresses[i]);
        end
        @(negedge clk);wr_en=0;
        // Consecutive reads cross all three banks. Requests are captured on
        // edge t; the registered adapter responds just after edge t+1.
        for(integer i=0;i<9;i=i+1) begin
            rd_en=(i<8);
            if(i<8) rd_addr=10'(addresses[i]);
            @(posedge clk);#1;
            if(i>0 && rd_data!==pattern(addresses[i-1]))
                $fatal(1,"Banked SRAM response mismatch index=%0d data=%h",i-1,rd_data);
            @(negedge clk);
        end
        held=rd_data;rd_en=0;rd_addr=999;
        repeat(6) begin @(posedge clk);#2;if(rd_data!==held) $fatal(1,"Disabled read did not hold");end
        @(negedge clk);wr_en=1;wr_addr=0;wr_data=19'h12345;rd_en=1;rd_addr=256;
        @(negedge clk);wr_en=0;rd_en=0;
        @(posedge clk);#1;
        if(rd_data!==pattern(256)) $fatal(1,"Independent same-offset banks interfered");
        $display("PASS: Banked SRAM registered reads, hold, depth tails and independent ports");$finish;
    end
    initial begin #10000;$fatal(1,"SRAM unit test timeout");end
endmodule
