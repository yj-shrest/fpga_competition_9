`timescale 1ns / 1ps

module neuron
#(
    parameter NEURON_WIDTH = 8,       // Number of inputs
    parameter DATA_BITS    = 16,      // Bit width of each input data value
    parameter WEIGHT_BITS  = 32,      // Bit width of each weight value
    parameter BIAS_BITS    = 16,      // Bit width of bias value
    parameter WeightFile   = "edge_encoder_w_1_0.mif",
    parameter BiasFile     = "edge_encoder_b_1_0.mif"
)
(
    input  clk,
    input  rstn,
    input  activation_function,

    /* Input data array */
    input  signed [NEURON_WIDTH*DATA_BITS-1:0] data_in_flat,

    input  [31:0] counter,

    output signed [DATA_BITS-1:0] data_out
);

    /* Memory arrays for weights and bias */
    reg signed [WEIGHT_BITS-1:0] weights [0:NEURON_WIDTH-1];
    reg signed [BIAS_BITS-1:0] bias_mem [0:0];
    wire signed [BIAS_BITS-1:0] bias;
    
    /* Flattened weight array for register module */
    wire signed [NEURON_WIDTH*WEIGHT_BITS-1:0] weights_flat;
    
    /* Internal buses */
    wire signed [WEIGHT_BITS-1:0]              bus_w;
    wire signed [DATA_BITS-1:0]                bus_data;
    wire signed [DATA_BITS+WEIGHT_BITS-1:0]    bus_mult_result;
    wire signed [DATA_BITS+WEIGHT_BITS+8:0]    bus_adder;

    /* Load weights and bias from MIF files */
    integer i;
    initial begin
        // Load weights
        $readmemb(WeightFile, weights);
        
        // Load bias
        $readmemb(BiasFile, bias_mem);
        
        // Display loaded values for debugging
        $display("Loaded weights from %s:", WeightFile);
        for (i = 0; i < NEURON_WIDTH; i = i + 1) begin
            $display("  weights[%0d] = %d", i, weights[i]);
        end
        $display("Loaded bias from %s: %d", BiasFile, bias_mem[0]);
    end
    
    /* Connect bias memory to wire */
    assign bias = bias_mem[0];
    
    /* Flatten weights array for the register module */
    genvar j;
    generate
        for (j = 0; j < NEURON_WIDTH; j = j + 1) begin : flatten_weights
            assign weights_flat[j*WEIGHT_BITS +: WEIGHT_BITS] = weights[j];
        end
    endgenerate

    /* Weight register selector */
    register
    #(
        .WIDTH(NEURON_WIDTH),
        .BITS(WEIGHT_BITS)
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
        .BITS(DATA_BITS)
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
        .DATA_BITS   (DATA_BITS),
        .WEIGHT_BITS (WEIGHT_BITS)
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
        .DATA_BITS   (DATA_BITS),
        .WEIGHT_BITS (WEIGHT_BITS)
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
        .DATA_BITS   (DATA_BITS),
        .WEIGHT_BITS (WEIGHT_BITS),
        .COUNTER_END (NEURON_WIDTH),
        .BIAS_BITS   (BIAS_BITS)
    )
    activation_and_add_b
    (
        .clk                 (clk),
        .rstn                (rstn),
        .mult_sum_in         (bus_adder),
        .counter             (counter),
        .activation_function (activation_function),
        .b                   (bias),
        .neuron_out          (data_out)
    );

endmodule