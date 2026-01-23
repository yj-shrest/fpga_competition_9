#!/usr/bin/env python3
"""
Generate Verilog node_encoder_layer module with 32 neurons and internal counter
"""

def generate_layer_module(num_features=32, num_neurons=32, block_no=1, layer_no=1):
    code = f"""`timescale 1ns / 1ps

module MP_Edge_Layer_B{block_no}_L{layer_no}
#(
    parameter LAYER_NO       = {layer_no},
    parameter NUM_NEURONS    = {num_neurons},
    parameter NUM_FEATURES   = {num_features},
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8
)
(
    input  clk,
    input  rstn,
    input  activation_function,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat,
    output signed [NUM_NEURONS*DATA_BITS-1:0] data_out_flat,
    output done
);

    // Internal counter signals
    wire [31:0] counter;
    wire counter_done;
    
    // Instantiate internal counter
    counter #(
        .END_COUNTER(NUM_FEATURES)
    ) layer_counter (
        .clk(clk),
        .rstn(rstn),
        .counter_out(counter),
        .counter_donestatus(counter_done)
    );
    
    // Done signal driven by counter
    assign done = counter_done;

    // Individual neuron outputs
    wire signed [DATA_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];
    
    // Generate neurons
    generate
"""
    
    # Generate each neuron
    for i in range(num_neurons):
        code += f"""
        // Neuron {i}
        if (NUM_NEURONS > {i}) begin : neuron_{i}
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_edge_w_1_{layer_no}_{i}.mif"),
                .BiasFile     ("mp_edge_b_1_{layer_no}_{i}.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[{i}])
            );
            assign data_out_flat[{i}*DATA_BITS +: DATA_BITS] = neuron_outputs[{i}];
        end
"""
    
    code += """
    endgenerate
    
    // Debug
    initial begin
        $display("========================================");
        $display("Edge Encoder Layer %0d Initialized", LAYER_NO);
        $display("  Number of Neurons: %0d", NUM_NEURONS);
        $display("  Input Features:    %0d", NUM_FEATURES);
        $display("========================================");
    end

endmodule
"""
    
    return code

if __name__ == "__main__":
    # Generate the module
    for block_no in range(2,8):
        layer_no = 3
        verilog_code = generate_layer_module(num_features=32, num_neurons=32, block_no=block_no, layer_no=layer_no)
        
        # Write to file
        with open(f"MP_Edge_Layer_B{block_no}_L{layer_no}.v", "w") as f:
            f.write(verilog_code)

        print(f"Generated MP_Edge_Layer_B{block_no}_L{layer_no}.v with 32 neurons and internal counter!")