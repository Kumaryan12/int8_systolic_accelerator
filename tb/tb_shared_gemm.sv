`timescale 1ns/1ps
module tb_shared_gemm #(parameter int M=3,K=5,N=7,OW=16+$clog2(K),JOBS=1);
    reg clk=0,rst_n=0,start=0;
    always #5 clk=~clk;
    reg [M*K*8-1:0] a_matrix;
    reg [K*N*8-1:0] b_matrix;
    wire [M*N*OW-1:0] c_matrix;
    reg [M*N*OW-1:0] expected_acc;
    reg [M*N*8-1:0] expected_out;
    integer multiplier,shift_amount,relu_flag,fd,fields,cycles=0;
    string path;
    wire busy,done;
    wire [M*N*8-1:0] outputs;
    tiled_gemm #(.M(M),.K(K),.N(N)) dut(.*);
    for(genvar i=0;i<M*N;i++) begin
        requantize #(.IN_W(OW)) q(.value(c_matrix[OW*i+:OW]),.multiplier(multiplier[30:0]),
            .shift(shift_amount[5:0]),.zero_point(8'sd0),.relu(relu_flag[0]),.result(outputs[8*i+:8]));
    end
    initial begin
        if(!$value$plusargs("INPUT=%s",path)) $fatal(1,"Missing input");
        fd=$fopen(path,"r");
        if(!fd) $fatal(1,"Cannot open vectors");
        repeat(3) @(negedge clk);
        rst_n=1;
        for(integer job=0;job<JOBS;job++) begin
            fields=$fscanf(fd,"%h %h %h %h %d %d %d",a_matrix,b_matrix,expected_acc,expected_out,multiplier,shift_amount,relu_flag);
            if(fields!=7) $fatal(1,"Malformed shared vectors");
            @(negedge clk); start=1;
            @(posedge clk); #1;
            if(!busy) $fatal(1,"Job not accepted");
            @(negedge clk); start=0;
            while(!done) begin @(posedge clk); #1; cycles++; end
            if(c_matrix!==expected_acc || outputs!==expected_out) $fatal(1,"Shared GEMM mismatch job=%0d",job);
        end
        $fclose(fd);
        $display("PASS: shared GEMM cycles=%0d outputs=%0d jobs=%0d",cycles,JOBS*M*N,JOBS);
        $finish;
    end
    initial begin #10_000_000; $fatal(1,"Timeout"); end
endmodule
