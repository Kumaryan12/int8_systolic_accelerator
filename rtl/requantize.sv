// Integer-only output scaling: round half away from zero, add zero point,
// optionally apply ReLU, then saturate to signed INT8.
module requantize #(parameter int IN_W=32) (
    input logic signed [IN_W-1:0] value,
    input logic [30:0] multiplier,
    input logic [5:0] shift,
    input logic signed [7:0] zero_point,
    input logic relu,
    output logic signed [7:0] result
);
    localparam int PRODUCT_W=IN_W+32;
    logic signed [PRODUCT_W-1:0] product;
    logic [PRODUCT_W:0] magnitude, rounding, rounded;
    logic signed [PRODUCT_W+1:0] scaled;

    always_comb begin
        product=value*$signed({1'b0,multiplier});
        magnitude=product[PRODUCT_W-1] ? -$signed({product[PRODUCT_W-1],product}) : {1'b0,product};
        rounding='0;
        if (shift != 0) rounding={{PRODUCT_W{1'b0}},1'b1} << (shift-1);
        rounded=(magnitude+rounding) >> shift;
        scaled=product[PRODUCT_W-1] ? -$signed({1'b0,rounded}) : $signed({1'b0,rounded});
        scaled=scaled+$signed(zero_point);
        if (relu && scaled<$signed(zero_point)) scaled=$signed(zero_point);
        if (scaled>127) result=8'sd127;
        else if (scaled < -128) result=-8'sd128;
        else result=scaled[7:0];
    end
endmodule
