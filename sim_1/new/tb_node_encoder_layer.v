`timescale 1ns / 1ps

module tb_node_encoder_layer;

    // Parameters
    parameter LAYER_NO       = 1;
    parameter NUM_NEURONS    = 32;
    parameter NUM_FEATURES   = 12;
    parameter DATA_BITS      = 8;
    parameter WEIGHT_BITS    = 8;
    parameter BIAS_BITS      = 8;    
    parameter CLK_PERIOD = 10;  // 10ns clock period (100MHz)
    
    // Testbench signals
    reg clk;
    reg rstn;
    reg activation_function;
    reg signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat;
    wire signed [NUM_NEURONS*DATA_BITS-1:0] data_out_flat;
    wire done;
    
    // For easier input assignment
    reg signed [DATA_BITS-1:0] input_features [0:NUM_FEATURES-1];
    
    // For easier output reading
    wire signed [DATA_BITS-1:0] output_neurons [0:NUM_NEURONS-1];
    
    // Unpack outputs for easier viewing
    genvar j;
    generate
        for (j = 0; j < NUM_NEURONS; j = j + 1) begin : unpack_outputs
            assign output_neurons[j] = data_out_flat[j*DATA_BITS +: DATA_BITS];
        end
    endgenerate
    
    // DUT instantiation
    node_encoder_layer_2 #(
        .LAYER_NO       (LAYER_NO),
        .NUM_NEURONS    (NUM_NEURONS),
        .NUM_FEATURES   (NUM_FEATURES),
        .DATA_BITS      (DATA_BITS),
        .WEIGHT_BITS    (WEIGHT_BITS),
        .BIAS_BITS      (BIAS_BITS)
    ) dut (
        .clk                 (clk),
        .rstn                (rstn),
        .activation_function (activation_function),
        .data_in_flat        (data_in_flat),
        .data_out_flat       (data_out_flat),
        .done                (done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Pack input features into flat vector
    integer i;
    always @(*) begin
        for (i = 0; i < NUM_FEATURES; i = i + 1) begin
            data_in_flat[i*DATA_BITS +: DATA_BITS] = input_features[i];
        end
    end
    
    // Test stimulus
    initial begin
        // Initialize
        rstn = 0;
        activation_function = 0;  // 0 = ReLU, 1 = Sigmoid (or your activation)
        
        // Initialize input features to simple values
        input_features[0] = 8'sd10;   // +10
        input_features[1] = 8'sd20;   // +20
        input_features[2] = 8'sd30;   // +30
        input_features[3] = -8'sd5;   // -5
        input_features[4] = 8'sd15;   // +15
        input_features[5] = -8'sd10;  // -10
        input_features[5] = -8'sd10;  // -10
        input_features[6] = 8'sd25;   // +25
        input_features[7] = -8'sd15;  // -15
        input_features[8] = 8'sd35;   // +35
        input_features[9] = -8'sd20;  // -20
        input_features[10] = 8'sd40;  // +40
        input_features[11] = -8'sd25; // -25

        $display("========================================");
        $display("Node Encoder Layer Testbench");
        $display("========================================");
        $display("Parameters:");
        $display("  NUM_NEURONS   = %0d", NUM_NEURONS);
        $display("  NUM_FEATURES  = %0d", NUM_FEATURES);
        $display("  DATA_BITS     = %0d", DATA_BITS);
        $display("========================================");
        
        // Display input data
        $display("\nInput Features:");
        for (i = 0; i < NUM_FEATURES; i = i + 1) begin
            $display("  Feature[%0d] = %0d", i, input_features[i]);
        end
        $display("========================================\n");
        
        // Reset
        #(CLK_PERIOD*2);
        rstn = 1;
        $display("Time=%0t: Reset deasserted, starting computation...\n", $time);
        
        // Wait for done signal
        wait(done == 1);
        #(CLK_PERIOD);
        
        // Display outputs
        $display("Time=%0t: Computation complete (done=1)\n", $time);
        $display("Output Neurons:");
        $display("----------------------------------------");
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin
            $display("  Neuron[%2d] = %0d (0x%h)", i, output_neurons[i], output_neurons[i]);
        end
        $display("========================================\n");
        
        // Run a bit longer
        #(CLK_PERIOD*5);
        
        // Test with different activation function
        $display("Testing with activation_function = 1\n");
        rstn = 0;
        activation_function = 1;
        #(CLK_PERIOD*2);
        rstn = 1;
        
        wait(done == 1);
        #(CLK_PERIOD);
        
        $display("Time=%0t: Computation complete with activation=1\n", $time);
        $display("Output Neurons:");
        $display("----------------------------------------");
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin
            $display("  Neuron[%2d] = %0d (0x%h)", i, output_neurons[i], output_neurons[i]);
        end
        $display("========================================\n");
        
        #(CLK_PERIOD*10);
        
        $display("Simulation completed successfully!");
        $finish;
    end
    
    // Monitor done signal
    always @(posedge done) begin
        $display(">>> DONE signal asserted at time %0t <<<", $time);
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 1000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // Optional: Generate VCD for waveform viewing
    initial begin
        $dumpfile("node_encoder_layer_tb.vcd");
        $dumpvars(0, tb_node_encoder_layer);
    end

endmodule