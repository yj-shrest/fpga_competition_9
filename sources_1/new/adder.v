`timescale 1ns / 1ps
module adder
#(
    parameter DATA_BITS   = 16,
    parameter WEIGHT_BITS = 32
)
(
    input  clk,
    input  rstn,
    input  [31:0] counter,
    input  signed [DATA_BITS+WEIGHT_BITS-1:0] value_in,
    output reg signed [DATA_BITS+WEIGHT_BITS+8:0] value_out
);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            value_out <= {(DATA_BITS+WEIGHT_BITS+9){1'b0}};
        end
        else if (counter == 0) begin
            // Start fresh accumulation at counter 0
            value_out <= value_in;
        end
        else begin
            // Continue accumulating
            value_out <= value_out + value_in;
        end
    end

endmodule