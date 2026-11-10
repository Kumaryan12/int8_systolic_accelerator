`timescale 1ns/1ps
// One clock domain: asynchronous assertion, two-clock synchronous release.
// Physical integration must preserve and place these two stages together.
module reset_sync(input wire clk, arst_n, output wire srst_n);
    (* async_reg = "true", keep = "true" *) reg [1:0] release_pipe;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) release_pipe <= 2'b00;
        else release_pipe <= {release_pipe[0], 1'b1};
    assign srst_n = release_pipe[1];
endmodule
