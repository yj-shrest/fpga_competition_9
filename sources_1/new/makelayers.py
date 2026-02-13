#!/usr/bin/env python3
"""
Generate Verilog node_encoder_layer module with 32 neurons and internal counter
"""

def generate_layer_module(num_features=32, num_neurons=32, block_no=1, layer_no=1):
    code = f"""`timescale 1ns / 1ps

module MP_Node_Layer_B{block_no}_L{layer_no}
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
    input  start,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat,
    output signed [NUM_NEURONS*DATA_BITS-1:0] data_out_flat,
    output done
);

    // Internal counter signals
    wire [31:0] counter;
    wire counter_done;
    reg computation_active;
    // Individual neuron outputs
    wire signed [DATA_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];
    // Add a delay register for done signal
    reg done_reg;
    reg [6:0] done_delay_counter;
    
    // Control computation active flag - FIXED STATE MACHINE
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            computation_active <= 0;
            done_reg <= 0;
            done_delay_counter <= 0;
        end else begin
            if (start && !computation_active && !done_reg) begin
                computation_active <= 1;  // Start computation
                done_reg <= 0;
                done_delay_counter <= 0;
                //$display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: Computation started", $time);
            end else if (counter_done && computation_active && !done_reg) begin
                // Counter is done, start done delay
                if (done_delay_counter < 1) begin  // Wait cycles for neurons to finish
                    done_delay_counter <= done_delay_counter + 1;
                    done_reg <= 0;
                    // $display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: Waiting for neurons, delay=%0d", 
                    //         $time, done_delay_counter);
                end else begin
                    // After delay, assert done (keep computation_active HIGH!)
                    //$display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: About to assert done - neuron outputs[0]=%h", 
                            //$time, neuron_outputs[0]);
                    //$display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: data_out_flat[31:0]=%h", 
                            //$time, data_out_flat[31:0]);
                    done_reg <= 1;
                    done_delay_counter <= 0;
                    //$display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: Computation completed, asserting done", $time);
                end
            end else if (done_reg && start) begin
                // New start signal received, clear done and restart
                computation_active <= 1;
                done_reg <= 0;
                done_delay_counter <= 0;
                //$display("[%0t] MP_Node_Layer_B{block_no}_L{layer_no}: Restarting computation", $time);
            end
        end
    end

    assign done = done_reg;

    // Instantiate internal counter
    counter #(
        .END_COUNTER(NUM_FEATURES)
    ) layer_counter (
        .clk(clk),
        .rstn(start),
        .counter_out(counter),
        .counter_donestatus(counter_done)
    );
        
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
                .WeightFile   ("mp_node_w_1_{layer_no}_{i}.mif"),
                .BiasFile     ("mp_node_b_1_{layer_no}_{i}.mif")
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

endmodule
"""
    
    return code

if __name__ == "__main__":
    # Generate the module
    for block_no in range(1,8):
        layer_no = 3
        verilog_code = generate_layer_module(num_features=32, num_neurons=32, block_no=block_no, layer_no=layer_no)
        
        # Write to file
        with open(f"MP_Node_Layer_B{block_no}_L{layer_no}.v", "w") as f:
            f.write(verilog_code)

        print(f"Generated MP_Node_Layer_B{block_no}_L{layer_no}.v with 32 neurons and internal counter!")