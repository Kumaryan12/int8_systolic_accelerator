`timescale 1ns/1ps
module tb_requantize;
    reg signed [31:0] value;
    reg [30:0] multiplier;
    reg [5:0] shift;
    reg signed [7:0] zero_point;
    reg relu;
    wire signed [7:0] result;
    integer fd, fields, expected, count=0;
    integer input_value, input_multiplier, input_shift, input_zero, input_relu;
    string vectors;
    requantize dut(.*);
    initial begin
        if (!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing VECTORS");
        fd=$fopen(vectors,"r");
        if (!fd) $fatal(1,"Cannot open quantization vectors");
        while (!$feof(fd)) begin
            fields=$fscanf(fd,"%d %d %d %d %d %d\n",input_value,input_multiplier,input_shift,input_zero,input_relu,expected);
            if (fields != 6) $fatal(1,"Malformed quantization vector");
            value=input_value; multiplier=input_multiplier; shift=input_shift;
            zero_point=input_zero; relu=input_relu;
            #1;
            if ($signed(result) !== expected)
                $fatal(1,"Requantize vector=%0d got=%0d expected=%0d",count,$signed(result),expected);
            count++;
        end
        $fclose(fd);
        if (count==0) $fatal(1,"No quantization vectors");
        $display("PASS: RTL requantization vectors=%0d",count);
        $finish;
    end
endmodule
