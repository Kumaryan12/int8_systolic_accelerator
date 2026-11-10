`timescale 1ns/1ps
module tb_memory_gemm #(
    parameter int M=3,K=5,N=7,TILE=4,JOBS=8,OVERLAP=1,STALLS=1
);
    localparam int AW=M*K,BW=K*N,CW=M*N,WORDS=AW+BW;
    localparam int OW=16+$clog2(K),IW=(CW>1 ? $clog2(CW) : 1);
    reg clk=0,rst_n=0,load_valid=0,load_bank=0,load_last=0,result_ready=0;
    always #5 clk=~clk;
    reg signed [7:0] load_data=0;
    reg [7:0] load_tag=0;
    wire load_ready,load_error,result_valid,result_bank,result_last,busy,compute_done;
    wire signed [OW-1:0] result_data;
    wire [7:0] result_tag,completed_tag;
    wire [IW-1:0] result_index;
    wire [1:0] bank_free;
    integer aa[0:JOBS-1][0:AW-1],bb[0:JOBS-1][0:BW-1],golden[0:JOBS-1][0:CW-1];
    integer received[0:JOBS-1];
    reg [31:0] tx_rng=2026,rx_rng=42,data_rng=20261110;
    reg run_active=0,was_stalled=0;
    reg [OW+IW+9:0] held_response;
    reg forced_stall[0:JOBS-1];
    integer cycles=0,loads=0,outputs=0,finished=0,computations=0;
    integer input_stalls=0,output_stalls=0,load_overlap=0,output_overlap=0;
    integer first_compute=-1,last_compute=-1,compute_intervals=0;
    memory_gemm #(.M(M),.K(K),.N(N),.TILE(TILE)) dut(.*);

    function integer rand_data;
        data_rng=data_rng*32'd1664525+32'd1013904223;
        rand_data=int'(data_rng[23:16])-128;
    endfunction
    task automatic send_word(input integer bank,tag,value,input bit last);
        load_bank=1'(bank); load_tag=8'(tag); load_data=8'(value); load_last=last; load_valid=1;
        @(posedge clk);
        while (!load_ready) @(posedge clk);
        @(negedge clk); load_valid=0;
    endtask
    task automatic frame(input integer job,bank,tag);
        for (integer p=0;p<WORDS;p++)
            send_word(bank,tag,p<AW ? aa[job][p] : bb[job][p-AW],p==WORDS-1);
    endtask
    task automatic reset_all;
        load_valid=0;
        #2; rst_n=0; #1;
        if (busy !== 0 || result_valid !== 0 || load_ready !== 0)
            $fatal(1,"Memory interface did not cancel asynchronously");
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        if (bank_free !== 2'b11) $fatal(1,"Memory slots not released by reset");
    endtask

    always @(negedge clk) begin
        if (run_active) begin
            rx_rng=rx_rng*32'd1664525+32'd1013904223;
            if (STALLS && result_valid && !forced_stall[result_tag]) begin
                result_ready=0;
                forced_stall[result_tag]=1;
            end else result_ready=!STALLS || (rx_rng[19:16]>=4);
        end else result_ready=0;
    end
    always @(posedge clk) begin
        if (!rst_n || !run_active) was_stalled=0;
        else begin
            cycles++;
            if (load_error) $fatal(1,"Unexpected input-frame error during valid workload");
            if (was_stalled && (!result_valid ||
                {result_bank,result_tag,result_index,result_last,result_data} !== held_response))
                $fatal(1,"Response changed under backpressure");
            was_stalled=result_valid && !result_ready;
            held_response={result_bank,result_tag,result_index,result_last,result_data};
            if (load_valid && !load_ready) input_stalls++;
            if (result_valid && !result_ready) output_stalls++;
            if (load_valid && load_ready) begin
                loads++;
                if (busy) load_overlap++;
            end
            if (compute_done) begin
                if (completed_tag>=JOBS) $fatal(1,"Reset-aborted tag completed later");
                computations++;
                if (first_compute<0) first_compute=cycles;
                if (last_compute>=0) compute_intervals+=cycles-last_compute;
                last_compute=cycles;
            end
            if (result_valid && result_ready) begin
                if (result_tag>=JOBS) $fatal(1,"Unknown/stale response tag %0d",result_tag);
                if (result_bank !== 1'(int'(result_tag)%2) || result_index !== IW'(received[result_tag]))
                    $fatal(1,"Result slot/index correlation failed");
                if ($signed(result_data) !== golden[result_tag][result_index])
                    $fatal(1,"Memory GEMM tag=%0d index=%0d got=%0d expected=%0d",result_tag,result_index,$signed(result_data),golden[result_tag][result_index]);
                if (result_last !== (received[result_tag]==CW-1)) $fatal(1,"Incorrect result last marker");
                received[result_tag]++;
                outputs++;
                if (busy) output_overlap++;
                if (result_last) finished++;
            end
        end
    end

    initial begin
        if ($value$plusargs("SEED=%d",data_rng)) begin end
        tx_rng=data_rng^32'h12345678;
        rx_rng=data_rng^32'h87654321;
        for (integer job=0;job<JOBS;job++) begin
            received[job]=0;
            forced_stall[job]=0;
            for (integer p=0;p<AW;p++)
                aa[job][p]=(job==0 ? -128 : job==1 ? 127 : job==2 ? 0 : rand_data());
            for (integer p=0;p<BW;p++)
                bb[job][p]=(job==0 ? -128 : job==1 ? -128 : job==2 ? 0 : rand_data());
            for (integer r=0;r<M;r++) begin
                for (integer c=0;c<N;c++) begin
                    golden[job][r*N+c]=0;
                    for (integer k=0;k<K;k++) golden[job][r*N+c]+=aa[job][r*K+k]*bb[job][k*N+c];
                end
            end
        end
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        // Early/missing last must discard the frame without launching a job.
        send_word(0,250,7,1);
        if (!load_error || busy) $fatal(1,"Early last was not rejected");
        for (integer p=0;p<WORDS;p++) send_word(0,250,7,0);
        if (!load_error || busy) $fatal(1,"Missing last was not rejected");
        send_word(1,250,7,0);
        reset_all();
        // Abort both active computation and an already-valid stalled response.
        frame(0,0,250);
        frame(1,1,251);
        wait(dut.tile_busy);
        repeat(2) @(negedge clk);
        reset_all();
        frame(0,0,250);
        wait(dut.c_write_en);
        @(negedge clk);
        reset_all();
        frame(0,0,250);
        wait(result_valid);
        repeat(5) @(negedge clk);
        reset_all();
        run_active=1;
        fork
            begin
                for (integer job=0;job<JOBS;job++) begin
                    if (!OVERLAP && job>0) begin
                        while (finished<job) begin @(posedge clk); #1; end
                        @(negedge clk);
                    end
                    for (integer p=0;p<WORDS;p++) begin
                        tx_rng=tx_rng*32'd1664525+32'd1013904223;
                        if (STALLS && tx_rng[19:16]<4) @(negedge clk);
                        send_word(job%2,job,p<AW ? aa[job][p] : bb[job][p-AW],p==WORDS-1);
                    end
                end
            end
            begin
                while (finished<JOBS) begin @(posedge clk); #1; end
            end
        join
        @(negedge clk);
        run_active=0;
        if (loads!=JOBS*WORDS || outputs!=JOBS*CW || computations!=JOBS || bank_free!==2'b11)
            $fatal(1,"Memory GEMM completeness check failed");
        if (OVERLAP && JOBS>=4 && (load_overlap==0 || output_overlap==0))
            $fatal(1,"Required transfer/compute overlap not observed");
        if (STALLS && (input_stalls==0 || output_stalls==0))
            $fatal(1,"Required backpressure not observed");
        $display("METRIC cycles=%0d loads=%0d outputs=%0d jobs=%0d load_overlap=%0d output_overlap=%0d input_stalls=%0d output_stalls=%0d compute_interval_sum=%0d",cycles,loads,outputs,JOBS,load_overlap,output_overlap,input_stalls,output_stalls,compute_intervals);
        $display("PASS: Memory GEMM shape=%0dx%0dx%0d overlap=%0d stalls=%0d",M,K,N,OVERLAP,STALLS);
        $finish;
    end
    initial begin #100_000_000; $fatal(1,"Memory GEMM global timeout"); end
endmodule
