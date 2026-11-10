`timescale 1ns/1ps
module memory_stream_sva #(parameter int OUT_W=19,INDEX_W=5,C_WORDS=21) (
    input logic clk,rst_n,
    input logic load_valid,load_ready,load_bank,load_last,
    input logic [7:0] load_data,load_tag,
    input logic result_valid,result_ready,result_bank,result_last,
    input logic [OUT_W-1:0] result_data,
    input logic [INDEX_W-1:0] result_index,
    input logic [7:0] result_tag,
    input logic busy,compute_done,result_owned,
    input logic a_collision,b_collision,c_collision
);
    input_holds: assert property (@(posedge clk) disable iff (!rst_n)
        (load_valid && !load_ready) |=> load_valid && $stable({load_bank,load_last,load_data,load_tag}));
    output_holds: assert property (@(posedge clk) disable iff (!rst_n)
        (result_valid && !result_ready) |=> result_valid &&
        $stable({result_bank,result_last,result_data,result_index,result_tag}));
    output_range: assert property (@(posedge clk) disable iff (!rst_n)
        result_valid |-> result_index<C_WORDS);
    output_marker: assert property (@(posedge clk) disable iff (!rst_n)
        result_valid |-> result_last==(result_index==C_WORDS-1));
    output_ownership: assert property (@(posedge clk) disable iff (!rst_n)
        result_valid |-> result_owned);
    completion_idle: assert property (@(posedge clk) disable iff (!rst_n)
        compute_done |-> !busy);
    ram_no_collision: assert property (@(posedge clk) disable iff (!rst_n)
        !(a_collision || b_collision || c_collision));
endmodule
