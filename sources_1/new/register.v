`timescale 1ns / 1ps
module register
#(
    parameter WIDTH = 8,
    parameter BITS  = 16
)
(
    input  signed [WIDTH*BITS-1:0] data_flat,
    input  [31:0] counter,
    output reg signed [BITS-1:0] value
);

    integer idx;

    always @(*) begin
        idx = counter;

        if (idx < WIDTH)
            value = data_flat[BITS*idx +: BITS];
        else
            value = {BITS{1'b0}};
    end

endmodule