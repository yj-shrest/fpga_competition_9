`timescale 1ns / 1ps

// ============================================
// MULTIPLIER MODULE
// ============================================
module multiplier
#(
    parameter DATA_BITS   = 16,
    parameter WEIGHT_BITS = 32
)
(
    input  clk,
    input  rstn,
    input  [31:0] counter,
    input  signed [WEIGHT_BITS-1:0] w,
    input  signed [DATA_BITS-1:0] x,
    output signed [DATA_BITS+WEIGHT_BITS-1:0] mult_result
);

    // Combinational multiplication
    assign mult_result = w * x;

endmodule