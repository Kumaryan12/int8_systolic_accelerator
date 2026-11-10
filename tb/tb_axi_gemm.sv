`timescale 1ns/1ps
module tb_axi_gemm;
    parameter integer M=3,K=5,N=7,TILE=4,SRAM_IMPL=0;
    localparam integer WORDS=M*K+K*N, OUTPUTS=M*N, JOBS=4;
    reg aclk=0, aresetn=0;
    always #5 aclk=~aclk;
    reg [7:0] s_axi_awaddr=0, s_axi_araddr=0;
    reg [2:0] s_axi_awprot=0, s_axi_arprot=0;
    reg s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0,s_axi_arvalid=0,s_axi_rready=0;
    wire s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid,irq;
    reg [31:0] s_axi_wdata=0;
    reg [3:0] s_axi_wstrb=0;
    wire [1:0] s_axi_bresp,s_axi_rresp;
    wire [31:0] s_axi_rdata;
`ifdef PHYSICAL_AXI
    axi_gemm_gate dut(.*);
`else
    axi_gemm #(.M(M),.K(K),.N(N),.TILE(TILE),.SRAM_IMPL(SRAM_IMPL)) dut(.*);
`endif
    integer seed=20261110, rng, discarded, writes=0,reads=0,resets=0;
    integer expected[0:JOBS-1][0:OUTPUTS-1];
    integer operands[0:JOBS-1][0:WORDS-1];
    reg [31:0] value,meta,status;
    integer j,i,r,c,k,total,mode,stall;

    task automatic ticks(input integer count);
        repeat(count) @(negedge aclk);
    endtask
    task automatic send_aw(input reg[7:0] addr);
        @(negedge aclk); s_axi_awaddr=addr; s_axi_awvalid=1;
        do @(posedge aclk); while(!s_axi_awready);
        @(negedge aclk); s_axi_awvalid=0;
    endtask
    task automatic send_w(input reg[31:0] data,input reg[3:0] strb);
        @(negedge aclk); s_axi_wdata=data; s_axi_wstrb=strb; s_axi_wvalid=1;
        do @(posedge aclk); while(!s_axi_wready);
        @(negedge aclk); s_axi_wvalid=0;
    endtask
    task automatic write_csr(input reg[7:0] addr,input reg[31:0] data,
                             input reg[3:0] strb,input integer order,input integer delay_b,input reg[1:0] resp);
        case(order)
            0: fork send_aw(addr); send_w(data,strb); join
            1: begin send_aw(addr); ticks(3); send_w(data,strb); end
            2: begin send_w(data,strb); ticks(3); send_aw(addr); end
        endcase
        while(!s_axi_bvalid) @(negedge aclk);
        repeat(delay_b) begin
            if (!s_axi_bvalid || s_axi_bresp!==resp || s_axi_awready || s_axi_wready)
                $fatal(1,"B payload/READY changed while stalled addr=%h",addr);
            @(negedge aclk);
        end
        if(s_axi_bresp!==resp) $fatal(1,"BRESP addr=%h got=%h expected=%h",addr,s_axi_bresp,resp);
        s_axi_bready=1; @(negedge aclk); s_axi_bready=0; writes=writes+1;
    endtask
    task automatic read_csr(input reg[7:0] addr,input integer delay_r,input reg[1:0] resp,output reg[31:0] data);
        @(negedge aclk); s_axi_araddr=addr; s_axi_arvalid=1;
        do @(posedge aclk); while(!s_axi_arready);
        @(negedge aclk); s_axi_arvalid=0;
        while(!s_axi_rvalid) @(negedge aclk);
        data=s_axi_rdata;
        repeat(delay_r) begin
            if(!s_axi_rvalid || s_axi_rdata!==data || s_axi_rresp!==resp || s_axi_arready)
                $fatal(1,"R payload/READY changed while stalled addr=%h",addr);
            @(negedge aclk);
        end
        if(s_axi_rresp!==resp) $fatal(1,"RRESP addr=%h got=%h",addr,s_axi_rresp);
        s_axi_rready=1; @(negedge aclk); s_axi_rready=0; reads=reads+1;
    endtask
    task automatic reset_device(input integer phase);
        @(negedge aclk); #(phase); aresetn=0;
        #1;
        if(s_axi_bvalid || s_axi_rvalid || s_axi_awready || s_axi_wready || s_axi_arready || irq)
            $fatal(1,"Asynchronous reset failed");
        s_axi_awvalid=0;s_axi_wvalid=0;s_axi_bready=0;s_axi_arvalid=0;s_axi_rready=0;
        ticks(3); #2 aresetn=1;
        @(posedge aclk); #1;
        if(s_axi_awready || s_axi_arready) $fatal(1,"Reset released before two clocks");
        @(posedge aclk); #1;
        if(!s_axi_awready || !s_axi_arready) $fatal(1,"Reset release did not complete");
        ticks(1);resets=resets+1;
    endtask
    task automatic load_job(input integer job);
        write_csr(8'h04, ((8'h60+job)<<8) | 16 | (job%2), 4'h3, job%3, 2, 0);
        for(integer x=0;x<WORDS;x=x+1) begin
            mode=$urandom_range(0,2); stall=$urandom_range(0,3);
            write_csr(8'h08,operands[job][x],4'h1,mode,stall,0);
        end
    endtask
    task automatic drain_job(input integer job);
        for(integer x=0;x<OUTPUTS;x=x+1) begin
            status=0;
            while(!status[3]) read_csr(8'h0c,0,0,status);
            read_csr(8'h10,$urandom_range(0,7),0,value);
            if($signed(value)!==expected[job][x])
                $fatal(1,"Result mismatch job=%0d index=%0d got=%0d expected=%0d",job,x,$signed(value),expected[job][x]);
            read_csr(8'h14,0,0,meta);
            if(meta!==(((8'h60+job)<<24) | ((x==OUTPUTS-1)<<23) | ((job%2)<<22) | x))
                $fatal(1,"Result metadata mismatch job=%0d index=%0d meta=%h",job,x,meta);
        end
    endtask

    initial begin
        if($value$plusargs("SEED=%d",seed)) begin end
        rng=seed; discarded=$urandom(rng);
        for(j=0;j<JOBS;j=j+1) begin
            for(i=0;i<WORDS;i=i+1) operands[j][i]=integer'($urandom_range(0,255))-128;
            for(r=0;r<M;r=r+1) for(c=0;c<N;c=c+1) begin
                total=0;
                for(k=0;k<K;k=k+1) total=total+operands[j][r*K+k]*operands[j][M*K+k*N+c];
                expected[j][r*N+c]=total;
            end
        end
        reset_device(1);
        read_csr(0,4,0,value); if(value!==32'h49385341) $fatal(1,"ID mismatch");
        read_csr(8'h24,0,0,value); if(value!==((M<<24)|(K<<16)|(N<<8)|TILE)) $fatal(1,"Dimensions");
        read_csr(8'h28,0,0,value); if(value!=WORDS) $fatal(1,"Input count");
        read_csr(8'h2c,0,0,value); if(value!=OUTPUTS) $fatal(1,"Output count");
        // Byte strobes: independently modify tag and bank/IRQ; no-op DATA.
        write_csr(4,32'h0000ab01,2,1,3,0);
        read_csr(4,0,0,value); if(value!==32'hab00) $fatal(1,"Tag strobe");
        write_csr(4,32'hdead0011,1,2,3,0);
        read_csr(4,0,0,value); if(value!==32'hab11) $fatal(1,"Bank strobe");
        write_csr(8,123,0,0,4,0);
        read_csr(8'h18,0,0,value); if(value!=0) $fatal(1,"Zero strobes loaded input");
        read_csr(8'h10,3,2,value); if(!irq) $fatal(1,"Error interrupt");
        read_csr(8'hff,1,2,value);read_csr(8'h01,1,2,value);
        write_csr(8'h00,0,15,0,2,2);write_csr(8'h09,0,15,1,2,2);
        write_csr(8'h20,2,1,2,2,0);
        if(irq) $fatal(1,"W1C did not clear error");
        // Reset cancels independently buffered address/data, a held B response,
        // partial frame, compute and a held successful result R response.
        send_aw(8'h04); reset_device(2);
        send_w(32'hffffffff,15); reset_device(3);
        fork send_aw(8'h04); send_w(32'hffffffff,15); join
        while(!s_axi_bvalid) ticks(1);
        reset_device(4);
        write_csr(8,7,1,0,0,0); reset_device(1);
        load_job(0); reset_device(2);
        load_job(0);
        status=0;while(!status[3]) read_csr(8'h0c,0,0,status);
        send_aw(8'h08); // Also cancel a pending address alongside stalled R.
        @(negedge aclk); s_axi_arvalid=1; s_axi_araddr=8'h10;
        do @(posedge aclk); while(!s_axi_arready);
        @(negedge aclk);s_axi_arvalid=0;
        if(!s_axi_rvalid) $fatal(1,"Missing pending result");
        reset_device(3);
        read_csr(8'h10,0,2,value);
        write_csr(8'h20,3,1,0,0,0);
        // Both banks can complete before either is consumed. Attempt a write
        // to an occupied bank while the independent read channel drains it.
        load_job(0);load_job(1);
        fork
            begin
                write_csr(4,16'h6210,3,0,0,0);
                write_csr(8,operands[2][0],1,2,5,0);
            end
            begin ticks(30);drain_job(0);drain_job(1); end
        join
        for(i=1;i<WORDS;i=i+1) write_csr(8,operands[2][i],1,i%3,0,0);
        load_job(3);drain_job(2);drain_job(3);
        read_csr(8'h18,0,0,value);if(value!=JOBS*WORDS) $fatal(1,"Input accounting");
        read_csr(8'h1c,0,0,value);if(value!=JOBS) $fatal(1,"Completion accounting");
        read_csr(8'h0c,0,0,value);if(value[2:0]!==3'b110) $fatal(1,"Banks not released");
        if(!irq) $fatal(1,"Completion interrupt missing");
        write_csr(8'h20,3,1,0,2,0);if(irq) $fatal(1,"Completion interrupt not cleared");
        $display("PASS: AXI GEMM shape=%0dx%0dx%0d jobs=%0d outputs=%0d resets=%0d writes=%0d reads=%0d seed=%0d",M,K,N,JOBS,JOBS*OUTPUTS,resets,writes,reads,seed);
        $finish;
    end
`ifdef VERILATOR
    // Public AXI response guarantees, sampled throughout the same host test.
    assert property (@(posedge aclk) disable iff(!aresetn)
        s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid && $stable(s_axi_bresp));
    assert property (@(posedge aclk) disable iff(!aresetn)
        s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid && $stable({s_axi_rdata,s_axi_rresp}));
    assert property (@(posedge aclk) disable iff(!aresetn)
        s_axi_bvalid |-> !s_axi_awready && !s_axi_wready);
    assert property (@(posedge aclk) disable iff(!aresetn)
        s_axi_rvalid |-> !s_axi_arready);
    assert property (@(posedge aclk) disable iff(!aresetn)
        dut.core.result_valid && !dut.core.result_ready |=> dut.core.result_valid &&
        $stable({dut.core.result_data,dut.core.result_tag,dut.core.result_index,dut.core.result_last}));
`endif
    initial begin #5000000; $fatal(1,"AXI test timeout"); end
endmodule
