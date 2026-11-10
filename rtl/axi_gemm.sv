`timescale 1ns/1ps
// 32-bit AXI4-Lite peripheral. One outstanding read and write, independently.
// See docs/axi_interface.md for the CSR map and software transaction contract.
module axi_gemm #(
    parameter integer M=3, K=5, N=7, TILE=4
)(
    input wire aclk, aresetn,
    input wire [7:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [7:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    output wire irq
);
    localparam integer OUT_W=16+$clog2(K);
    localparam integer INDEX_W=(M*N>1 ? $clog2(M*N) : 1);
    localparam integer INPUT_WORDS=M*K+K*N;
    localparam integer COUNT_W=$clog2(INPUT_WORDS+1);
    initial begin
        if (M<1 || K<1 || N<1 || TILE<1 || M>255 || K>255 || N>255 || TILE>255 || M*N>65535)
            $fatal(1,"AXI dimensions must fit the CSR fields and be positive");
    end
    wire reset_n;
    reset_sync reset_release(.clk(aclk), .arst_n(aresetn), .srst_n(reset_n));
    reg aw_pending, w_pending;
    reg [7:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg bank, irq_enable, done_sticky, error_sticky;
    reg [7:0] tag;
    reg [COUNT_W-1:0] input_count[0:1];
    reg [31:0] last_meta, input_beats, completed_jobs;
    reg read_holds_result;
    wire load_ready, load_error, result_valid, result_bank, result_last, busy, compute_done;
    wire signed [OUT_W-1:0] result_data;
    wire [7:0] result_tag;
    wire [INDEX_W-1:0] result_index;
    wire [1:0] bank_free;
    wire write_pending=aw_pending && w_pending && !s_axi_bvalid;
    wire load_valid=reset_n && write_pending && awaddr==8'h08 && wstrb[0];
    wire result_ready=s_axi_rvalid && s_axi_rready && read_holds_result;
    assign s_axi_awready=reset_n && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready=reset_n && !w_pending && !s_axi_bvalid;
    assign s_axi_arready=reset_n && !s_axi_rvalid;
    assign irq=irq_enable && (done_sticky || error_sticky);
    // AxPROT is accepted without privilege/security filtering. Integration must
    // enforce access control upstream if required by the system.
    wire unused_prot=^{s_axi_awprot,s_axi_arprot};
    memory_gemm #(.M(M),.K(K),.N(N),.TILE(TILE)) core (
        .clk(aclk),.rst_n(reset_n),.load_valid(load_valid),.load_ready(load_ready),
        .load_bank(bank),.load_data(wdata[7:0]),.load_tag(tag),
        .load_last(input_count[bank]==INPUT_WORDS-1),.load_error(load_error),
        .result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),
        .result_bank(result_bank),.result_tag(result_tag),.result_index(result_index),
        .result_last(result_last),.busy(busy),.compute_done(compute_done),
        .completed_tag(),.bank_free(bank_free)
    );

    always @(posedge aclk or negedge reset_n) begin
        if (!reset_n) begin
            aw_pending<=0; w_pending<=0; awaddr<=0; wdata<=0; wstrb<=0;
            s_axi_bvalid<=0; s_axi_bresp<=0;
            s_axi_rvalid<=0; s_axi_rdata<=0; s_axi_rresp<=0; read_holds_result<=0;
            bank<=0; tag<=0; irq_enable<=0; done_sticky<=0; error_sticky<=0;
            input_count[0]<=0; input_count[1]<=0;
            last_meta<=0; input_beats<=0; completed_jobs<=0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin aw_pending<=1; awaddr<=s_axi_awaddr; end
            if (s_axi_wvalid && s_axi_wready) begin w_pending<=1; wdata<=s_axi_wdata; wstrb<=s_axi_wstrb; end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            // A full/owned bank backpressures DATA until a concurrent reader
            // releases it. Status and reads remain available during this wait.
            if (write_pending && (!load_valid || load_ready)) begin
                aw_pending<=0; w_pending<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
                case (awaddr)
                    8'h04: begin
                        if (wstrb[0]) begin bank<=wdata[0]; irq_enable<=wdata[4]; end
                        if (wstrb[1]) tag<=wdata[15:8];
                    end
                    8'h08: if (wstrb[0]) begin
                        input_beats<=input_beats+1;
                        if (input_count[bank]==INPUT_WORDS-1) input_count[bank]<=0;
                        else input_count[bank]<=input_count[bank]+1'b1;
                    end
                    8'h20: if (wstrb[0]) begin
                        if (wdata[0]) done_sticky<=0;
                        if (wdata[1]) error_sticky<=0;
                    end
                    default: begin s_axi_bresp<=2'b10; error_sticky<=1; end
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid<=0; read_holds_result<=0;
            end
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1; s_axi_rresp<=0; s_axi_rdata<=0; read_holds_result<=0;
                case (s_axi_araddr)
                    8'h00: s_axi_rdata<=32'h49385341;
                    8'h04: s_axi_rdata<={16'b0,tag,3'b0,irq_enable,3'b0,bank};
                    8'h0c: s_axi_rdata<={23'b0,1'b1,error_sticky,done_sticky,2'b0,result_valid,bank_free,busy};
                    8'h10: if (result_valid) begin
                        s_axi_rdata<={{(32-OUT_W){result_data[OUT_W-1]}},result_data};
                        read_holds_result<=1;
                        last_meta<={result_tag,result_last,result_bank,6'b0,16'(result_index)};
                    end else begin s_axi_rresp<=2'b10; error_sticky<=1; end
                    8'h14: s_axi_rdata<=last_meta;
                    8'h18: s_axi_rdata<=input_beats;
                    8'h1c: s_axi_rdata<=completed_jobs;
                    8'h20: s_axi_rdata<={30'b0,error_sticky,done_sticky};
                    8'h24: s_axi_rdata<={8'(M),8'(K),8'(N),8'(TILE)};
                    8'h28: s_axi_rdata<=INPUT_WORDS;
                    8'h2c: s_axi_rdata<=M*N;
                    default: begin s_axi_rresp<=2'b10; error_sticky<=1; end
                endcase
            end
            // Hardware events win over a simultaneous W1C access.
            if (compute_done) begin done_sticky<=1; completed_jobs<=completed_jobs+1; end
            if (load_error) error_sticky<=1;
        end
    end
endmodule
