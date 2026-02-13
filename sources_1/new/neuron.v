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
    wire signed [DATA_BITS+WEIGHT_BITS-1:0]    bus_adder;

    /* Load weights and bias from MIF files */
    integer i;
    initial begin
        // Load weights
        $readmemb(WeightFile, weights);
        
        // Load bias
        $readmemb(BiasFile, bias_mem);
        
        // Check if weights loaded successfully
        if (weights[0] === {WEIGHT_BITS{1'bx}}) begin
            $display("[NEURON ERROR] Failed to load weights from %s - weights[0]=xx", WeightFile);
            $display("  -> File may not exist or has wrong format!");
            $display("  -> Expected: %0d lines of %0d-bit binary values", NEURON_WIDTH, WEIGHT_BITS);
        end else begin
            // $display("[NEURON SUCCESS] Loaded %s: w[0]=%h w[1]=%h bias=%h", 
            //          WeightFile, weights[0], weights[1], bias_mem[0]);
        end
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

    // Monitor at NEGATIVE edge - after posedge updates have settled
    always @(negedge clk) begin
        if (WeightFile == "decoder_w_1_1.mif" || WeightFile == "decoder_w_1_2.mif") begin
            if (rstn) begin  // Only display when not in reset
                $display("[%0t] NEURON[%s] Counter=%0d | w=%h x=%h | mult=%6d | accum=%6d | bias=%4d | out=%4d", 
                         $time, WeightFile, counter, bus_w, bus_data, 
                         $signed(bus_mult_result), $signed(bus_adder), 
                         $signed(bias), $signed(data_out));
                
                // Show detailed breakdown at key counter values
                if (counter == 1) begin
                    $display("    [FIRST CYCLE] Starting MAC operation");
                end
                if (counter == NEURON_WIDTH) begin
                    $display("    [LAST INPUT] Final accumulation cycle - ReLU should activate");
                    $display("    Expected final sum in accum (before bias): %0d", $signed(bus_adder));
                end
            end
        end
    end

endmodule
