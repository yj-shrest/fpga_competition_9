`timescale 1ns / 1ps

module edge_output_transform
#(
    parameter LAYER_NO       = 2,
    parameter NUM_NEURONS    = 1,
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8
)
(
    input  clk,
    input  rstn,
    input  activation_function,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat,
    output signed [DATA_BITS-1:0] data_out_flat,
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

    // Single neuron output
    wire signed [DATA_BITS-1:0] neuron_output;
    
    // Instantiate single output neuron
    neuron #(
        .NEURON_WIDTH (NUM_FEATURES),
        .DATA_BITS    (DATA_BITS),
        .WEIGHT_BITS  (WEIGHT_BITS),
        .BIAS_BITS    (BIAS_BITS),
        .WeightFile   ("output_w_2_0.mif"),
        .BiasFile     ("output_b_2_0.mif")
    ) output_neuron (
        .clk                 (clk),
        .rstn                (rstn),
        .activation_function (activation_function),
        .data_in_flat        (data_in_flat),
        .counter             (counter),
        .data_out            (neuron_output)
    );
    
    // Assign output
    assign data_out_flat = neuron_output;
    
    // // Debug - detailed tracing
    // reg prev_rstn = 0;
    // always @(posedge clk) begin
    //     prev_rstn <= rstn;
        
    //     if (!rstn && prev_rstn) begin
    //         $display("[EDGE_OUTPUT_XFORM][%0t] *** ENTERING RESET ***", $time);
    //     end else if (rstn && !prev_rstn) begin
    //         $display("[EDGE_OUTPUT_XFORM][%0t] *** EXITING RESET - counter will start ***", $time);
    //     end else if (rstn) begin
    //         if (counter == 0) begin
    //             $display("[EDGE_OUTPUT_XFORM][%0t] START: counter=%0d, data_in[31:0]=%h_%h_%h_%h", 
    //                      $time, counter, data_in_flat[31:24], data_in_flat[23:16], 
    //                      data_in_flat[15:8], data_in_flat[7:0]);
    //         end
            
    //         if (counter == 1) begin
    //             $display("[EDGE_OUTPUT_XFORM][%0t] PROCESSING: counter=%0d, neuron_out=%h (should not be xx if weights loaded)", 
    //                      $time, counter, neuron_output);
    //         end
            
    //         if (counter_done) begin
    //             if (neuron_output === 8'bxxxxxxxx) begin
    //                 $display("[EDGE_OUTPUT_XFORM][%0t] ERROR: neuron_out=xx! Counter=%0d, rstn=%b", 
    //                         $time, counter, rstn);
    //                 $display("[EDGE_OUTPUT_XFORM][%0t]   -> This means neuron weights did NOT load from output_w_0.mif!", $time);
    //             end else begin
    //                 $display("[EDGE_OUTPUT_XFORM][%0t] SUCCESS: counter=%0d, neuron_out=%h (decimal %0d)", 
    //                         $time, counter, neuron_output, $signed(neuron_output));
    //             end
    //         end
    //     end
    // end
    
    // Debug
    initial begin
        $display("========================================");
        $display("Edge Output Transform Layer Initialized");
        $display("  Input Features:  %0d", NUM_FEATURES);
        $display("  Output:          1 value (%0d bits)", DATA_BITS);
        $display("========================================");
    end

endmodule
