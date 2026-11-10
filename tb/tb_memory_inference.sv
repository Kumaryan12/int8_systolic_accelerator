`timescale 1ns/1ps
module tb_memory_inference;
    localparam int M=3,K=5,N=7,OW=19,IW=5,WORDS=M*K+K*N;
    reg clk=0,rst_n=0,load_valid=0,load_bank=0,load_last=0,result_ready=0;
    always #5 clk=~clk;
    reg signed [7:0] load_data=0;
    reg [7:0] load_tag=7;
    wire load_ready,load_error,result_valid,result_bank,result_last,busy,compute_done;
    wire signed [OW-1:0] result_data;
    wire [7:0] result_tag,completed_tag;
    wire [IW-1:0] result_index;
    wire [1:0] bank_free;
    wire signed [7:0] quantized;
    reg [M*K*8-1:0] a_matrix;
    reg [K*N*8-1:0] b_matrix;
    integer multiplier,shift_amount,fd,out_fd,fields,count=0,cycles=0;
    integer first_load=-1,last_load=-1,finished_compute=-1,first_output=-1;
    reg measuring=0;
    string input_path,output_path,wave_path;
    memory_gemm #(.M(M),.K(K),.N(N)) dut(.*);
    requantize #(.IN_W(OW)) postprocess (
        .value(result_data),.multiplier(multiplier[30:0]),.shift(shift_amount[5:0]),
        .zero_point(8'sd0),.relu(1'b1),.result(quantized)
    );
    always @(negedge clk) result_ready=measuring && (cycles%7!=3);
    always @(posedge clk) if (measuring) begin
        cycles++;
        if (load_error) $fatal(1,"Inference frame was rejected");
        if (load_valid && load_ready) begin
            if (first_load<0) first_load=cycles;
            if (load_last) last_load=cycles;
        end
        if (compute_done) finished_compute=cycles;
        if (result_valid && result_ready) begin
            if (first_output<0) first_output=cycles;
            if (result_bank!==0 || result_tag!==8'd7 || result_index!==IW'(count) || result_last!==(count==M*N-1))
                $fatal(1,"Memory inference response correlation failed");
            $fdisplay(out_fd,"%0d %0d",$signed(result_data),$signed(quantized));
            count++;
        end
    end
    initial begin
        if (!$value$plusargs("INPUT=%s",input_path) || !$value$plusargs("OUTPUT=%s",output_path))
            $fatal(1,"Missing memory inference paths");
        if ($value$plusargs("WAVE=%s",wave_path)) begin $dumpfile(wave_path); $dumpvars(0,tb_memory_inference); end
        fd=$fopen(input_path,"r");
        if (!fd) $fatal(1,"Cannot open memory inference input");
        fields=$fscanf(fd,"%h %h %d %d",a_matrix,b_matrix,multiplier,shift_amount);
        $fclose(fd);
        if (fields!=4) $fatal(1,"Malformed memory inference vector");
        out_fd=$fopen(output_path,"w");
        if (!out_fd) $fatal(1,"Cannot open memory inference output");
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        measuring=1;
        for (integer p=0;p<WORDS;p++) begin
            load_data=(p<M*K ? a_matrix[8*p +: 8] : b_matrix[8*(p-M*K) +: 8]);
            load_last=(p==WORDS-1); load_valid=1;
            @(posedge clk);
            while (!load_ready) @(posedge clk);
            @(negedge clk);
        end
        load_valid=0;
        while (count<M*N) begin @(posedge clk); #1; end
        @(negedge clk); measuring=0;
        $fclose(out_fd);
        if (finished_compute<last_load || bank_free!==2'b11) $fatal(1,"Memory inference completion failed");
        $display("MEMORY_INFERENCE cycles=%0d first_load=%0d last_load=%0d compute_done=%0d first_output=%0d",cycles,first_load,last_load,finished_compute,first_output);
        $display("PASS: Memory inference outputs=21");
        $finish;
    end
    initial begin #100_000; $fatal(1,"Memory inference timeout"); end
endmodule
