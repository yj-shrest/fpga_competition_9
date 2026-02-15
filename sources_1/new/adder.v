`timescale 1ns / 1ps
module adder
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8
)
(
    input  clk,
    input  rstn,
    input  [31:0] counter,
    input  signed [DATA_BITS+WEIGHT_BITS-1:0] value_in,
    output reg signed [DATA_BITS+WEIGHT_BITS-1:0] value_out,
    output reg overflow  // Optional: flag overflow condition
);
    localparam ACCUM_BITS = DATA_BITS + WEIGHT_BITS + 8;
    localparam OUT_BITS = DATA_BITS + WEIGHT_BITS;
    
    // Maximum and minimum representable values for signed output
    localparam signed [OUT_BITS-1:0] MAX_VAL = {1'b0, {(OUT_BITS-1){1'b1}}};  // 0x7FFF...
    localparam signed [OUT_BITS-1:0] MIN_VAL = {1'b1, {(OUT_BITS-1){1'b0}}};  // 0x8000...
    
    reg signed [ACCUM_BITS-1:0] accumulator;
    reg signed [ACCUM_BITS-1:0] temp_sum;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            accumulator <= {ACCUM_BITS{1'b0}};
            value_out <= {OUT_BITS{1'b0}};
            overflow <= 1'b0;
        end
        else if (counter == 1) begin
            // Start fresh accumulation at counter 1
            accumulator <= {{8{value_in[OUT_BITS-1]}}, value_in};
            value_out <= value_in;
            overflow <= 1'b0;
        end
        else if (counter >= 2) begin
            // Continue accumulating
            temp_sum = accumulator + {{8{value_in[OUT_BITS-1]}}, value_in};
            accumulator <= temp_sum;
            
            // Check for overflow and clamp
            if (temp_sum[ACCUM_BITS-1:OUT_BITS-1] != {9{temp_sum[OUT_BITS-1]}}) begin
                // Overflow detected
                overflow <= 1'b1;
                
                // Clamp based on sign of accumulator
                if (temp_sum[ACCUM_BITS-1] == 1'b0) begin
                    // Positive overflow - clamp to MAX
                    value_out <= MAX_VAL;
                end
                else begin
                    // Negative overflow - clamp to MIN
                    value_out <= MIN_VAL;
                end
            end
            else begin
                // No overflow - normal output
                overflow <= 1'b0;
                value_out <= temp_sum[OUT_BITS-1:0];
            end
        end
        else begin
            // Counter 0 - hold zero
            value_out <= {OUT_BITS{1'b0}};
            overflow <= 1'b0;
        end
    end

endmodule