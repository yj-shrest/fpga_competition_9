`timescale 1ns / 1ps
module ReLu
#(
    parameter DATA_BITS   = 16,
    parameter WEIGHT_BITS = 32,
    parameter COUNTER_END = 8,
    parameter BIAS_BITS   = 16
)
(
    input  clk,
    input  rstn,
    input  activation_function,   // 1 = ReLU, 0 = linear
    input  [31:0] counter,
    input  signed [DATA_BITS+WEIGHT_BITS+8:0] mult_sum_in,
    input  signed [BIAS_BITS-1:0] b,
    output reg signed [DATA_BITS-1:0] neuron_out
);

    reg signed [DATA_BITS+WEIGHT_BITS+8:0] biased_sum;
    
    // Saturation limits for DATA_BITS
    localparam signed [DATA_BITS-1:0] MAX_VAL = {1'b0, {(DATA_BITS-1){1'b1}}}; // Maximum positive value
    localparam signed [DATA_BITS-1:0] MIN_VAL = {1'b1, {(DATA_BITS-1){1'b0}}}; // Minimum negative value

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            neuron_out <= {DATA_BITS{1'b0}};
        end
        else if (counter >= COUNTER_END) begin
            biased_sum = mult_sum_in + b;

            if (activation_function) begin
                /* ReLU with saturation */
                if (biased_sum < 0)
                    neuron_out <= {DATA_BITS{1'b0}};  // Clamp to 0
                else if (biased_sum > MAX_VAL)
                    neuron_out <= MAX_VAL;  // Saturate to max positive
                else
                    neuron_out <= biased_sum[DATA_BITS-1:0];  // Normal output
            end
            else begin
                /* Linear with saturation */
                if (biased_sum > MAX_VAL)
                    neuron_out <= MAX_VAL;  // Saturate positive
                else if (biased_sum < MIN_VAL)
                    neuron_out <= MIN_VAL;  // Saturate negative
                else
                    neuron_out <= biased_sum[DATA_BITS-1:0];  // Normal output
            end
        end
        else begin
            neuron_out <= {DATA_BITS{1'b0}};
        end
    end

endmodule