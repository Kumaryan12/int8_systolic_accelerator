`timescale 1ns/1ps
module tb_inference;
    localparam int M=3, K=5, N=7, OUT_W=19;
    reg clk=0, rst_n=0, start=0;
    always #5 clk=~clk;
    reg [M*K*8-1:0] a_matrix='0;
    reg [K*N*8-1:0] b_matrix='0;
    wire [M*N*OUT_W-1:0] c_matrix;
    wire busy, done;
    wire signed [7:0] output_value[0:M*N-1];
    integer multiplier, shift_amount, fd, fields, cycles;
    string input_path, output_path, wave_path;
    tiled_gemm #(.M(M), .K(K), .N(N)) dut(.*);
    for (genvar i=0; i<M*N; i++) begin : OUTPUTS
        requantize #(.IN_W(OUT_W)) postprocess (
            .value(c_matrix[OUT_W*i +: OUT_W]), .multiplier(multiplier[30:0]),
            .shift(shift_amount[5:0]), .zero_point(8'sd0), .relu(1'b1), .result(output_value[i])
        );
    end
    initial begin
        if (!$value$plusargs("INPUT=%s",input_path) || !$value$plusargs("OUTPUT=%s",output_path))
            $fatal(1,"Missing inference input/output paths");
        if ($value$plusargs("WAVE=%s",wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0,tb_inference);
        end
        fd=$fopen(input_path,"r");
        if (!fd) $fatal(1,"Cannot open inference input");
        fields=$fscanf(fd,"%h %h %d %d",a_matrix,b_matrix,multiplier,shift_amount);
        $fclose(fd);
        if (fields!=4) $fatal(1,"Malformed inference input");
        repeat (3) @(negedge clk);
        rst_n=1;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        cycles=0;
        while (!done && cycles<60) begin @(posedge clk); #1; cycles++; end
        if (!done || busy || cycles!=48) $fatal(1,"Inference completion/latency failed");
        fd=$fopen(output_path,"w");
        if (!fd) $fatal(1,"Cannot open inference output");
        for (integer i=0; i<M*N; i++)
            $fdisplay(fd,"%0d %0d",$signed(c_matrix[OUT_W*i +: OUT_W]),$signed(output_value[i]));
        $fclose(fd);
        $display("PASS: Inference RTL completed outputs=21 cycles=%0d",cycles);
        repeat (2) @(posedge clk);
        #1;
        if (done || busy) $fatal(1,"Inference done did not return to idle");
        $finish;
    end
endmodule
