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
    output reg signed [DATA_BITS+WEIGHT_BITS-1:0] value_out
);
    reg signed [DATA_BITS+WEIGHT_BITS+8-1:0] accumulator;
    reg signed [DATA_BITS+WEIGHT_BITS+8-1:0] temp_sum;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            accumulator <= {(DATA_BITS+WEIGHT_BITS+8){1'b0}};
            value_out <= {(DATA_BITS+WEIGHT_BITS){1'b0}};
        end
        else if (counter == 1) begin
            // Start fresh accumulation at counter 1
            accumulator <= {{8{value_in[DATA_BITS+WEIGHT_BITS-1]}}, value_in};
            value_out <= value_in;
            // $display("[%0t] Adder: Counter=%d START, value_in=%d, value_out=%d", 
            //          $time, counter, $signed(value_in), $signed(value_in));
        end
        else if (counter >= 2) begin  // REMOVED the "<= 6" condition!
            // Continue accumulating
            temp_sum = accumulator + {{8{value_in[DATA_BITS+WEIGHT_BITS-1]}}, value_in};
            accumulator <= temp_sum;
            value_out <= temp_sum[DATA_BITS+WEIGHT_BITS-1:0];
            // $display("[%0t] Adder: Counter=%d, value_in=%d, old_accum=%d, new_value_out=%d", 
            //          $time, counter, $signed(value_in), $signed(accumulator[DATA_BITS+WEIGHT_BITS-1:0]), 
            //          $signed(temp_sum[DATA_BITS+WEIGHT_BITS-1:0]));
        end
        else begin
            // Counter 0 - hold zero
            value_out <= {(DATA_BITS+WEIGHT_BITS){1'b0}};
        end
    end

endmodule