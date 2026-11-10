// Signed multiply-accumulate processing element for a systolic array.
// Inputs are consumed on a rising edge and forwarded one cycle later.
module mac_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 18
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         clear,
    input  logic                         enable,
    input  logic signed [DATA_W-1:0]     a_in,
    input  logic signed [DATA_W-1:0]     b_in,
    output logic signed [DATA_W-1:0]     a_out,
    output logic signed [DATA_W-1:0]     b_out,
    output logic signed [ACC_W-1:0]      acc_out
);
    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0] product_ext;

    assign product = a_in * b_in;
    assign product_ext = {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out   <= '0;
            b_out   <= '0;
            acc_out <= '0;
        end else if (clear) begin
            a_out   <= '0;
            b_out   <= '0;
            acc_out <= '0;
        end else if (enable) begin
            a_out   <= a_in;
            b_out   <= b_in;
            acc_out <= acc_out + product_ext;
        end
    end
endmodule
