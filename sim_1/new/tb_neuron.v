`timescale 1ns / 1ps

module tb_neuron_mif();

    // Parameters
    parameter NEURON_WIDTH = 6;
    parameter DATA_BITS    = 16;
    parameter WEIGHT_BITS  = 32;
    parameter BIAS_BITS    = 16;

    // Signals
    reg  clk;
    reg  rstn;
    reg  activation_function;
    reg  signed [NEURON_WIDTH*DATA_BITS-1:0] data_in_flat;
    reg  [31:0] counter;
    wire signed [DATA_BITS+WEIGHT_BITS:0] data_out;

    // DUT - weights and bias loaded from MIF files
    neuron 
    #(
        .NEURON_WIDTH (NEURON_WIDTH),
        .DATA_BITS    (DATA_BITS),
        .WEIGHT_BITS  (WEIGHT_BITS),
        .BIAS_BITS    (BIAS_BITS),
        .WeightFile   ("edge_encoder_w_1_0.mif"),
        .BiasFile     ("edge_encoder_b_1_0.mif")
    )
    DUT
    (
        .clk                 (clk),
        .rstn                (rstn),
        .activation_function (activation_function),
        .data_in_flat        (data_in_flat),
        .counter             (counter),
        .data_out            (data_out)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Monitor
    always @(posedge clk) begin
        if (rstn) begin
            $display("Time=%0t | Counter=%0d | Data_out=%0d", $time, counter, data_out);
        end
    end

    // Test
    initial begin
        $display("======================================");
        $display("Testing Neuron with MIF Files");
        $display("DATA_BITS=%0d, WEIGHT_BITS=%0d, BIAS_BITS=%0d", 
                 DATA_BITS, WEIGHT_BITS, BIAS_BITS);
        $display("======================================");
        
        // Initialize
        rstn = 0;
        counter = 0;
        activation_function = 1; // ReLU on
        
        // Data = [1, 1, 1, 1, 1, 1]
        data_in_flat[0*DATA_BITS +: DATA_BITS] = 16'd1;
        data_in_flat[1*DATA_BITS +: DATA_BITS] = 16'd1;
        data_in_flat[2*DATA_BITS +: DATA_BITS] = 16'd1;
        data_in_flat[3*DATA_BITS +: DATA_BITS] = 16'd1;
        data_in_flat[4*DATA_BITS +: DATA_BITS] = 16'd1;
        data_in_flat[5*DATA_BITS +: DATA_BITS] = 16'd1;
        
        // Reset
        #20;
        rstn = 1;
        #10;
        
        $display("\n=== STARTING COMPUTATION ===\n");
        
        // Run through all counters
        counter = 0; #10;
        counter = 1; #10;
        counter = 2; #10;
        counter = 3; #10;
        counter = 4; #10;
        counter = 5; #10;
        counter = 6; #10;
        
        // Wait for result
        #50;
        
        $display("\n======================================");
        $display("FINAL RESULT:");
        $display("Output: %0d", data_out);
        $display("======================================");
        
        #20;
        $finish;
    end

endmodule