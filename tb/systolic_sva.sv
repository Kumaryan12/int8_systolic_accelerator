`timescale 1ns/1ps
// Temporal properties use pre-edge samples; age counts completed compute edges.
module systolic_sva #(
    parameter int N=4, DATA_W=8, ACC_W=2*DATA_W+$clog2(N)
) (
    input logic clk, rst_n, start, busy, done,
    input logic [N*N*ACC_W-1:0] c_matrix
);
    localparam int LATENCY=3*N-2;
    int unsigned age;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) age <= 0;
        else if (start && !busy) age <= 0;
        else if (busy) age <= age + 1;

    accept_clears: assert property (@(posedge clk) disable iff (!rst_n)
        (start && !busy) |=> (busy && !done && c_matrix == '0));
    controls_exclusive: assert property (@(posedge clk) disable iff (!rst_n)
        !(busy && done));
    done_pulse: assert property (@(posedge clk) disable iff (!rst_n)
        done |=> !done);
    no_early_completion: assert property (@(posedge clk) disable iff (!rst_n)
        (busy && age < LATENCY-1) |=> (busy && !done));
    exact_completion: assert property (@(posedge clk) disable iff (!rst_n)
        (busy && age == LATENCY-1) |=> (!busy && done));
    idle_holds: assert property (@(posedge clk) disable iff (!rst_n)
        (!busy && !start) |=> $stable(c_matrix));
endmodule
