`timescale 1ns/1ps
// Two tagged job slots in three synchronous 1R1W scratchpads. Input frames
// contain row-major A followed by row-major B. A completed frame is dispatched
// automatically; result words carry their slot, tag, index and last marker.
module memory_gemm #(
    parameter int M=3, K=5, N=7, TILE=4, DATA_W=8, TAG_W=8, SRAM_IMPL=0,
    parameter int OUT_W=2*DATA_W+$clog2(K),
    parameter int INDEX_W=(M*N>1 ? $clog2(M*N) : 1)
) (
    input logic clk, rst_n,
    input logic load_valid,
    output wire load_ready,
    input logic load_bank,
    input logic signed [DATA_W-1:0] load_data,
    input logic [TAG_W-1:0] load_tag,
    input logic load_last,
    output logic load_error,
    output logic result_valid,
    input logic result_ready,
    output wire signed [OUT_W-1:0] result_data,
    output logic result_bank,
    output logic [TAG_W-1:0] result_tag,
    output logic [INDEX_W-1:0] result_index,
    output wire result_last,
    output wire busy,
    output logic compute_done,
    output logic [TAG_W-1:0] completed_tag,
    output wire [1:0] bank_free
);
    localparam int A_WORDS=M*K, B_WORDS=K*N, C_WORDS=M*N;
    localparam int INPUT_WORDS=A_WORDS+B_WORDS, TW=TILE*TILE;
    localparam int LOAD_W=$clog2(INPUT_WORDS+1), FILL_W=$clog2(TW+1);
    localparam int WORD_W=(TW>1 ? $clog2(TW) : 1), READ_W=$clog2(C_WORDS+1);
    localparam int A_AW=$clog2(2*A_WORDS), B_AW=$clog2(2*B_WORDS), C_AW=$clog2(2*C_WORDS);
    localparam int TILE_ACC_W=2*DATA_W+$clog2(TILE);
    localparam logic [2:0] FREE=0, LOADING=1, READY=2, RUNNING=3, RESULT=4;
    typedef enum logic [2:0] {E_IDLE,E_FILL,E_LAUNCH,E_WAIT,E_WRITE} engine_state_t;
    engine_state_t engine;
    logic [2:0] slot_state[0:1];
    logic [LOAD_W-1:0] load_count[0:1];
    logic [TAG_W-1:0] tags[0:1];
    // An extra metadata stage accompanies the registered macro response.
    logic macro_fill_pending, macro_a_valid, macro_b_valid;
    logic [WORD_W-1:0] macro_fill_index;
    logic c_pending;
    logic [INDEX_W-1:0] c_pending_index;
    logic active_bank;
    logic [$clog2(M+TILE)-1:0] row_base;
    logic [$clog2(N+TILE)-1:0] col_base;
    logic [$clog2(K+TILE)-1:0] k_base;
    logic [FILL_W-1:0] fill_issue;
    logic fill_pending, pending_a_valid, pending_b_valid;
    logic [WORD_W-1:0] pending_index, write_index;
    logic [TW*DATA_W-1:0] tile_a, tile_b;
    wire [TW*TILE_ACC_W-1:0] tile_c;
    logic [TW*OUT_W-1:0] tile_acc;
    wire tile_done, tile_busy;
    wire tile_start=(engine==E_LAUNCH);
    logic draining;
    logic [READ_W-1:0] next_read;
    wire [DATA_W-1:0] a_read, b_read;
    wire [OUT_W-1:0] c_read;
    integer fill_r, fill_c, write_r, write_c;
    wire consume_fill=SRAM_IMPL ? macro_fill_pending : fill_pending;
    wire consume_a=SRAM_IMPL ? macro_a_valid : pending_a_valid;
    wire consume_b=SRAM_IMPL ? macro_b_valid : pending_b_valid;
    wire [WORD_W-1:0] consume_index=SRAM_IMPL ? macro_fill_index : pending_index;


    assign busy=(engine!=E_IDLE);
    assign bank_free={(slot_state[1]==FREE),(slot_state[0]==FREE)};
    assign load_ready=rst_n && (slot_state[load_bank]==FREE || slot_state[load_bank]==LOADING);
    wire load_fire=load_valid && load_ready;
    wire expected_last=(load_count[load_bank]==INPUT_WORDS-1);
    wire load_good=load_fire && (load_last==expected_last);
    wire a_write_en=load_good && (load_count[load_bank]<A_WORDS);
    wire b_write_en=load_good && (load_count[load_bank]>=A_WORDS);

    always_comb begin
        fill_r=int'(fill_issue)/TILE;
        fill_c=int'(fill_issue)%TILE;
        write_r=int'(write_index)/TILE;
        write_c=int'(write_index)%TILE;
    end
    wire issuing=(engine==E_FILL && fill_issue<TW);
    wire a_read_en=issuing && (row_base+fill_r<M) && (k_base+fill_c<K);
    wire b_read_en=issuing && (k_base+fill_r<K) && (col_base+fill_c<N);
    wire c_write_en=(engine==E_WRITE && row_base+write_r<M && col_base+write_c<N);
    wire c_read_en=draining && (!SRAM_IMPL || !c_pending) && (!result_valid || result_ready) && next_read<C_WORDS;

    sync_dp_ram #(.WIDTH(DATA_W),.DEPTH(2*A_WORDS),.IMPLEMENTATION(SRAM_IMPL)) a_memory (
        .clk(clk),.wr_en(a_write_en),.wr_addr(A_AW'(int'(load_bank)*A_WORDS+int'(load_count[load_bank]))),
        .wr_data(load_data),.rd_en(a_read_en),
        .rd_addr(A_AW'(int'(active_bank)*A_WORDS+(int'(row_base)+fill_r)*K+int'(k_base)+fill_c)),.rd_data(a_read)
    );
    sync_dp_ram #(.WIDTH(DATA_W),.DEPTH(2*B_WORDS),.IMPLEMENTATION(SRAM_IMPL)) b_memory (
        .clk(clk),.wr_en(b_write_en),.wr_addr(B_AW'(int'(load_bank)*B_WORDS+int'(load_count[load_bank])-A_WORDS)),
        .wr_data(load_data),.rd_en(b_read_en),
        .rd_addr(B_AW'(int'(active_bank)*B_WORDS+(int'(k_base)+fill_r)*N+int'(col_base)+fill_c)),.rd_data(b_read)
    );
    sync_dp_ram #(.WIDTH(OUT_W),.DEPTH(2*C_WORDS),.IMPLEMENTATION(SRAM_IMPL)) c_memory (
        .clk(clk),.wr_en(c_write_en),
        .wr_addr(C_AW'(int'(active_bank)*C_WORDS+(int'(row_base)+write_r)*N+int'(col_base)+write_c)),
        .wr_data(tile_acc[OUT_W*int'(write_index) +: OUT_W]),.rd_en(c_read_en),
        .rd_addr(C_AW'(int'(result_bank)*C_WORDS+int'(next_read))),.rd_data(c_read)
    );
    assign result_data=$signed(c_read);
    assign result_last=(result_index==C_WORDS-1);

    systolic_array #(.N(TILE),.DATA_W(DATA_W),.ACC_W(TILE_ACC_W)) tile (
        .clk(clk),.rst_n(rst_n),.start(tile_start),.a_matrix(tile_a),.b_matrix(tile_b),
        .busy(tile_busy),.done(tile_done),.c_matrix(tile_c)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            engine<=E_IDLE;
            active_bank<=0;
            row_base<=0; col_base<=0; k_base<=0;
            fill_issue<=0; fill_pending<=0;
            macro_fill_pending<=0; macro_a_valid<=0; macro_b_valid<=0; macro_fill_index<=0;
            c_pending<=0; c_pending_index<=0;
            pending_a_valid<=0; pending_b_valid<=0; pending_index<=0;
            write_index<=0; tile_a<='0; tile_b<='0; tile_acc<='0;
            draining<=0; next_read<=0;
            result_valid<=0; result_bank<=0; result_tag<=0; result_index<=0;
            compute_done<=0; completed_tag<=0; load_error<=0;
            for (int bank=0; bank<2; bank++) begin
                slot_state[bank]<=FREE;
                load_count[bank]<=0;
                tags[bank]<=0;
            end
        end else begin
            load_error<=0;
            compute_done<=0;
            // A bad frame is discarded. Every word of a later valid frame
            // must be received before its old RAM contents can be consumed.
            if (load_fire) begin
                if (load_last!=expected_last) begin
                    load_error<=1;
                    load_count[load_bank]<=0;
                    slot_state[load_bank]<=FREE;
                end else begin
                    if (slot_state[load_bank]==FREE) tags[load_bank]<=load_tag;
                    if (expected_last) begin
                        load_count[load_bank]<=0;
                        slot_state[load_bank]<=READY;
                    end else begin
                        load_count[load_bank]<=load_count[load_bank]+1'b1;
                        slot_state[load_bank]<=LOADING;
                    end
                end
            end

            // Inferred RAM can directly register each outgoing word. Macro
            // responses use one in-flight request and a held response, giving
            // one result every two clocks without overwriting a stalled word.
            if (!draining) begin
                if (slot_state[0]==RESULT || slot_state[1]==RESULT) begin
                    result_bank<=(slot_state[0]==RESULT ? 1'b0 : 1'b1);
                    result_tag<=(slot_state[0]==RESULT ? tags[0] : tags[1]);
                    next_read<=0;
                    draining<=1;
                end
            end else begin
                if (SRAM_IMPL) begin
                    c_pending<=c_read_en;
                    if(result_valid && result_ready) result_valid<=0;
                    if(c_read_en) begin
                        c_pending_index<=INDEX_W'(next_read);
                        next_read<=next_read+1'b1;
                    end
                    if(c_pending) begin result_valid<=1; result_index<=c_pending_index; end
                end else begin
                    if (c_read_en) begin
                        result_valid<=1;
                        result_index<=INDEX_W'(next_read);
                        next_read<=next_read+1'b1;
                    end else if (result_valid && result_ready) result_valid<=0;
                end
                if (result_valid && result_ready && result_last) begin
                    slot_state[result_bank]<=FREE;
                    load_count[result_bank]<=0;
                    result_valid<=0;
                    draining<=0;
                end
            end
            if(SRAM_IMPL) begin
                macro_fill_pending<=fill_pending;
                if(fill_pending) begin
                    macro_fill_index<=pending_index;
                    macro_a_valid<=pending_a_valid;
                    macro_b_valid<=pending_b_valid;
                end
            end

            case (engine)
                E_IDLE: if (slot_state[0]==READY || slot_state[1]==READY) begin
                    active_bank<=(slot_state[0]==READY ? 1'b0 : 1'b1);
                    slot_state[slot_state[0]==READY ? 0 : 1]<=RUNNING;
                    row_base<=0; col_base<=0; k_base<=0;
                    fill_issue<=0; fill_pending<=0; tile_acc<='0;
                    engine<=E_FILL;
                end
                E_FILL: begin
                    fill_pending<=issuing;
                    if (issuing) begin
                        pending_index<=WORD_W'(fill_issue);
                        pending_a_valid<=a_read_en;
                        pending_b_valid<=b_read_en;
                        fill_issue<=fill_issue+1'b1;
                    end
                    if (consume_fill) begin
                        tile_a[DATA_W*int'(consume_index) +: DATA_W]<=consume_a ? a_read : '0;
                        tile_b[DATA_W*int'(consume_index) +: DATA_W]<=consume_b ? b_read : '0;
                        if (consume_index==TW-1) begin
                            fill_pending<=0;
                            engine<=E_LAUNCH;
                        end
                    end
                end
                E_LAUNCH: engine<=E_WAIT;
                E_WAIT: if (tile_done) begin
                    for (int i=0; i<TW; i++)
                        tile_acc[OUT_W*i +: OUT_W]<=
                            $signed(tile_acc[OUT_W*i +: OUT_W])+$signed(tile_c[TILE_ACC_W*i +: TILE_ACC_W]);
                    if (k_base+TILE<K) begin
                        k_base<=k_base+TILE;
                        fill_issue<=0;
                        engine<=E_FILL;
                    end else begin
                        write_index<=0;
                        engine<=E_WRITE;
                    end
                end
                E_WRITE: begin
                    if (write_index==TW-1) begin
                        k_base<=0; fill_issue<=0; tile_acc<='0;
                        if (col_base+TILE<N) begin
                            col_base<=col_base+TILE;
                            engine<=E_FILL;
                        end else if (row_base+TILE<M) begin
                            col_base<=0;
                            row_base<=row_base+TILE;
                            engine<=E_FILL;
                        end else begin
                            slot_state[active_bank]<=RESULT;
                            compute_done<=1;
                            completed_tag<=tags[active_bank];
                            engine<=E_IDLE;
                        end
                    end else write_index<=write_index+1'b1;
                end
                default: engine<=E_IDLE;
            endcase
        end
    end
endmodule
