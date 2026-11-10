`timescale 1ns/1ps
module tb_digit_classifier #(parameter int MAX_BATCHES=450);
    localparam int M=4,K=65,N=10,OW=23,IW=6,WORDS=M*K+K*N;
    reg clk=0,rst_n=0,load_valid=0,load_bank=0,load_last=0,result_ready=1;
    always #5 clk=~clk;
    reg signed [7:0] load_data=0;
    reg [7:0] load_tag=0;
    wire load_ready,load_error,result_valid,result_bank,result_last,busy,compute_done;
    wire signed [OW-1:0] result_data;
    wire [7:0] result_tag,completed_tag;
    wire [IW-1:0] result_index;
    wire [1:0] bank_free;
    reg [M*K*8-1:0] a_vectors[0:MAX_BATCHES-1];
    reg [K*N*8-1:0] b_vectors[0:MAX_BATCHES-1];
    reg [M*N*OW-1:0] golden_acc[0:MAX_BATCHES-1];
    reg [M*N*8-1:0] golden_out[0:MAX_BATCHES-1];
    wire signed [7:0] quantized;
    integer multiplier,shift_amount,batches,fd,out_fd,fields,received=0,total=0;
    string path,output_path;
    memory_gemm #(.M(M),.K(K),.N(N)) dut(.*);
    requantize #(.IN_W(OW)) postprocess (
        .value(result_data),.multiplier(multiplier[30:0]),.shift(shift_amount[5:0]),
        .zero_point(8'sd0),.relu(1'b0),.result(quantized)
    );
    always @(posedge clk) if (rst_n) begin
        if (load_error) $fatal(1,"Classifier input frame rejected");
        if (result_valid && result_ready) begin
            if (result_tag!==8'(received) || result_bank!==1'(received%2)) $fatal(1,"Classifier job ordering failed");
            if ($signed(result_data)!==$signed(golden_acc[received][OW*int'(result_index) +: OW]) ||
                $signed(quantized)!==$signed(golden_out[received][8*int'(result_index) +: 8]))
                $fatal(1,"Classifier logits mismatch batch=%0d index=%0d",received,result_index);
            $fdisplay(out_fd,"%0d %0d",$signed(result_data),$signed(quantized));
            total++;
            if (result_last) received++;
        end
    end
    initial begin
        if (!$value$plusargs("VECTORS=%s",path) || !$value$plusargs("OUTPUT=%s",output_path)) $fatal(1,"Missing classifier paths");
        fd=$fopen(path,"r"); out_fd=$fopen(output_path,"w");
        if (!fd || !out_fd) $fatal(1,"Cannot open classifier vectors/output");
        fields=$fscanf(fd,"%d %d %d\n",multiplier,shift_amount,batches);
        if (fields!=3 || batches!=MAX_BATCHES) $fatal(1,"Unexpected classifier header");
        for (integer batch=0;batch<batches;batch++) begin
            fields=$fscanf(fd,"%h %h %h %h\n",a_vectors[batch],b_vectors[batch],golden_acc[batch],golden_out[batch]);
            if (fields!=4) $fatal(1,"Malformed classifier vector");
        end
        $fclose(fd);
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk);
        for (integer batch=0;batch<batches;batch++) begin
            for (integer word_index=0;word_index<WORDS;word_index++) begin
                load_valid=1; load_bank=1'(batch%2); load_tag=8'(batch); load_last=(word_index==WORDS-1);
                load_data=(word_index<M*K ? a_vectors[batch][8*word_index +: 8] : b_vectors[batch][8*(word_index-M*K) +: 8]);
                @(posedge clk); while (!load_ready) @(posedge clk);
                @(negedge clk);
            end
        end
        load_valid=0;
        while (received<batches) begin @(posedge clk); #1; end
        @(negedge clk); $fclose(out_fd);
        if (total!=MAX_BATCHES*M*N) $fatal(1,"Classifier output count failed");
        $display("PASS: Trained RTL classifier batches=%0d outputs=%0d",received,total);
        $finish;
    end
    initial begin #100_000_000; $fatal(1,"Classifier global timeout"); end
endmodule
