`timescale 1ns / 1ps

module neuron
#(
    parameter NEURON_WIDTH = 8,
    parameter NEURON_BITS  = 16,
    parameter COUNTER_END  = 8,
    parameter B_BITS       = 16
)
(
    input  clk,
    input  rstn,
    input  activation_function,

    /* Flattened arrays */
    input  signed [NEURON_WIDTH*32-1:0]           weights_flat,
    input  signed [NEURON_WIDTH*(NEURON_BITS+1)-1:0] data_in_flat,

    input  signed [B_BITS:0] b,
    input  [31:0] counter,

    output signed [NEURON_BITS+8:0] data_out
);

    /* Internal buses */
    wire signed [31:0]               bus_w;
    wire signed [NEURON_BITS:0]      bus_data;
    wire signed [NEURON_BITS+16:0]   bus_mult_result;
    wire signed [NEURON_BITS+24:0]   bus_adder;

    /* Weight register selector */
    register
    #(
        .WIDTH(NEURON_WIDTH),
        .BITS(32)
    )
    RG_W
    (
        .data_flat (weights_flat),
        .counter   (counter),
        .value     (bus_w)
    );

    /* Input data register selector */
    register
    #(
        .WIDTH(NEURON_WIDTH),
        .BITS(NEURON_BITS+1)
    )
    RG_X
    (
        .data_flat (data_in_flat),
        .counter   (counter),
        .value     (bus_data)
    );

    /* Multiply */
    multiplier
    #(
        .BITS(NEURON_BITS)
    )
    MP1
    (
        .clk         (clk),
        .rstn        (rstn),
        .counter     (counter),
        .w           (bus_w),
        .x           (bus_data),
        .mult_result (bus_mult_result)
    );

    /* Accumulate */
    adder
    #(
        .BITS(NEURON_BITS)
    )
    AD1
    (
        .clk       (clk),
        .rstn      (rstn),
        .counter   (counter),
        .value_in  (bus_mult_result),
        .value_out (bus_adder)
    );

    /* Activation + bias */
    ReLu
    #(
        .BITS        (NEURON_BITS),
        .COUNTER_END (COUNTER_END),
        .B_BITS      (B_BITS)
    )
    activation_and_add_b
    (
        .clk                 (clk),
        .mult_sum_in         (bus_adder),
        .counter             (counter),
        .activation_function (activation_function),
        .b                   (b),
        .neuron_out           (data_out)
    );

endmodule
