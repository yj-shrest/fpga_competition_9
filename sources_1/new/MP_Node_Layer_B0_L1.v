`timescale 1ns / 1ps

module MP_Node_Layer_B0_L1
#(
    parameter LAYER_NO       = 1,
    parameter NUM_NEURONS    = 32,
    parameter NUM_FEATURES   = 128,
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
                $display("[%0t] MP_Node_Layer_B0_L1: Computation started", $time);
            end else if (counter_done && computation_active && !done_reg) begin
                // Counter is done, start done delay
                if (done_delay_counter < 50) begin  // Wait cycles for neurons to finish
                    done_delay_counter <= done_delay_counter + 1;
                    done_reg <= 0;
                    // $display("[%0t] MP_Node_Layer_B0_L1: Waiting for neurons, delay=%0d", 
                    //         $time, done_delay_counter);
                end else begin
                    done_reg <= 1;
                    done_delay_counter <= 0;
                    $display("[%0t] MP_Node_Layer_B0_L1: Computation completed, asserting done", $time);
                end
            end else if (done_reg && start) begin
                // New start signal received, clear done and restart
                computation_active <= 1;
                done_reg <= 0;
                done_delay_counter <= 0;
                $display("[%0t] MP_Node_Layer_B0_L1: Restarting computation", $time);
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
    
    // Individual neuron outputs
    wire signed [DATA_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];
    
    // Generate neurons
    generate

        // Neuron 0
        if (NUM_NEURONS > 0) begin : neuron_0
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_0.mif"),
                .BiasFile     ("mp_node_b_0_1_0.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[0])
            );
            assign data_out_flat[0*DATA_BITS +: DATA_BITS] = neuron_outputs[0];
        end

        // Neuron 1
        if (NUM_NEURONS > 1) begin : neuron_1
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_1.mif"),
                .BiasFile     ("mp_node_b_0_1_1.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[1])
            );
            assign data_out_flat[1*DATA_BITS +: DATA_BITS] = neuron_outputs[1];
        end

        // Neuron 2
        if (NUM_NEURONS > 2) begin : neuron_2
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_2.mif"),
                .BiasFile     ("mp_node_b_0_1_2.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[2])
            );
            assign data_out_flat[2*DATA_BITS +: DATA_BITS] = neuron_outputs[2];
        end

        // Neuron 3
        if (NUM_NEURONS > 3) begin : neuron_3
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_3.mif"),
                .BiasFile     ("mp_node_b_0_1_3.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[3])
            );
            assign data_out_flat[3*DATA_BITS +: DATA_BITS] = neuron_outputs[3];
        end

        // Neuron 4
        if (NUM_NEURONS > 4) begin : neuron_4
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_4.mif"),
                .BiasFile     ("mp_node_b_0_1_4.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[4])
            );
            assign data_out_flat[4*DATA_BITS +: DATA_BITS] = neuron_outputs[4];
        end

        // Neuron 5
        if (NUM_NEURONS > 5) begin : neuron_5
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_5.mif"),
                .BiasFile     ("mp_node_b_0_1_5.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[5])
            );
            assign data_out_flat[5*DATA_BITS +: DATA_BITS] = neuron_outputs[5];
        end

        // Neuron 6
        if (NUM_NEURONS > 6) begin : neuron_6
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_6.mif"),
                .BiasFile     ("mp_node_b_0_1_6.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[6])
            );
            assign data_out_flat[6*DATA_BITS +: DATA_BITS] = neuron_outputs[6];
        end

        // Neuron 7
        if (NUM_NEURONS > 7) begin : neuron_7
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_7.mif"),
                .BiasFile     ("mp_node_b_0_1_7.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[7])
            );
            assign data_out_flat[7*DATA_BITS +: DATA_BITS] = neuron_outputs[7];
        end

        // Neuron 8
        if (NUM_NEURONS > 8) begin : neuron_8
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_8.mif"),
                .BiasFile     ("mp_node_b_0_1_8.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[8])
            );
            assign data_out_flat[8*DATA_BITS +: DATA_BITS] = neuron_outputs[8];
        end

        // Neuron 9
        if (NUM_NEURONS > 9) begin : neuron_9
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_9.mif"),
                .BiasFile     ("mp_node_b_0_1_9.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[9])
            );
            assign data_out_flat[9*DATA_BITS +: DATA_BITS] = neuron_outputs[9];
        end

        // Neuron 10
        if (NUM_NEURONS > 10) begin : neuron_10
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_10.mif"),
                .BiasFile     ("mp_node_b_0_1_10.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[10])
            );
            assign data_out_flat[10*DATA_BITS +: DATA_BITS] = neuron_outputs[10];
        end

        // Neuron 11
        if (NUM_NEURONS > 11) begin : neuron_11
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_11.mif"),
                .BiasFile     ("mp_node_b_0_1_11.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[11])
            );
            assign data_out_flat[11*DATA_BITS +: DATA_BITS] = neuron_outputs[11];
        end

        // Neuron 12
        if (NUM_NEURONS > 12) begin : neuron_12
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_12.mif"),
                .BiasFile     ("mp_node_b_0_1_12.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[12])
            );
            assign data_out_flat[12*DATA_BITS +: DATA_BITS] = neuron_outputs[12];
        end

        // Neuron 13
        if (NUM_NEURONS > 13) begin : neuron_13
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_13.mif"),
                .BiasFile     ("mp_node_b_0_1_13.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[13])
            );
            assign data_out_flat[13*DATA_BITS +: DATA_BITS] = neuron_outputs[13];
        end

        // Neuron 14
        if (NUM_NEURONS > 14) begin : neuron_14
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_14.mif"),
                .BiasFile     ("mp_node_b_0_1_14.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[14])
            );
            assign data_out_flat[14*DATA_BITS +: DATA_BITS] = neuron_outputs[14];
        end

        // Neuron 15
        if (NUM_NEURONS > 15) begin : neuron_15
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_15.mif"),
                .BiasFile     ("mp_node_b_0_1_15.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[15])
            );
            assign data_out_flat[15*DATA_BITS +: DATA_BITS] = neuron_outputs[15];
        end

        // Neuron 16
        if (NUM_NEURONS > 16) begin : neuron_16
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_16.mif"),
                .BiasFile     ("mp_node_b_0_1_16.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[16])
            );
            assign data_out_flat[16*DATA_BITS +: DATA_BITS] = neuron_outputs[16];
        end

        // Neuron 17
        if (NUM_NEURONS > 17) begin : neuron_17
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_17.mif"),
                .BiasFile     ("mp_node_b_0_1_17.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[17])
            );
            assign data_out_flat[17*DATA_BITS +: DATA_BITS] = neuron_outputs[17];
        end

        // Neuron 18
        if (NUM_NEURONS > 18) begin : neuron_18
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_18.mif"),
                .BiasFile     ("mp_node_b_0_1_18.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[18])
            );
            assign data_out_flat[18*DATA_BITS +: DATA_BITS] = neuron_outputs[18];
        end

        // Neuron 19
        if (NUM_NEURONS > 19) begin : neuron_19
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_19.mif"),
                .BiasFile     ("mp_node_b_0_1_19.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[19])
            );
            assign data_out_flat[19*DATA_BITS +: DATA_BITS] = neuron_outputs[19];
        end

        // Neuron 20
        if (NUM_NEURONS > 20) begin : neuron_20
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_20.mif"),
                .BiasFile     ("mp_node_b_0_1_20.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[20])
            );
            assign data_out_flat[20*DATA_BITS +: DATA_BITS] = neuron_outputs[20];
        end

        // Neuron 21
        if (NUM_NEURONS > 21) begin : neuron_21
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_21.mif"),
                .BiasFile     ("mp_node_b_0_1_21.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[21])
            );
            assign data_out_flat[21*DATA_BITS +: DATA_BITS] = neuron_outputs[21];
        end

        // Neuron 22
        if (NUM_NEURONS > 22) begin : neuron_22
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_22.mif"),
                .BiasFile     ("mp_node_b_0_1_22.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[22])
            );
            assign data_out_flat[22*DATA_BITS +: DATA_BITS] = neuron_outputs[22];
        end

        // Neuron 23
        if (NUM_NEURONS > 23) begin : neuron_23
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_23.mif"),
                .BiasFile     ("mp_node_b_0_1_23.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[23])
            );
            assign data_out_flat[23*DATA_BITS +: DATA_BITS] = neuron_outputs[23];
        end

        // Neuron 24
        if (NUM_NEURONS > 24) begin : neuron_24
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_24.mif"),
                .BiasFile     ("mp_node_b_0_1_24.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[24])
            );
            assign data_out_flat[24*DATA_BITS +: DATA_BITS] = neuron_outputs[24];
        end

        // Neuron 25
        if (NUM_NEURONS > 25) begin : neuron_25
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_25.mif"),
                .BiasFile     ("mp_node_b_0_1_25.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[25])
            );
            assign data_out_flat[25*DATA_BITS +: DATA_BITS] = neuron_outputs[25];
        end

        // Neuron 26
        if (NUM_NEURONS > 26) begin : neuron_26
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_26.mif"),
                .BiasFile     ("mp_node_b_0_1_26.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[26])
            );
            assign data_out_flat[26*DATA_BITS +: DATA_BITS] = neuron_outputs[26];
        end

        // Neuron 27
        if (NUM_NEURONS > 27) begin : neuron_27
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_27.mif"),
                .BiasFile     ("mp_node_b_0_1_27.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[27])
            );
            assign data_out_flat[27*DATA_BITS +: DATA_BITS] = neuron_outputs[27];
        end

        // Neuron 28
        if (NUM_NEURONS > 28) begin : neuron_28
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_28.mif"),
                .BiasFile     ("mp_node_b_0_1_28.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[28])
            );
            assign data_out_flat[28*DATA_BITS +: DATA_BITS] = neuron_outputs[28];
        end

        // Neuron 29
        if (NUM_NEURONS > 29) begin : neuron_29
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_29.mif"),
                .BiasFile     ("mp_node_b_0_1_29.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[29])
            );
            assign data_out_flat[29*DATA_BITS +: DATA_BITS] = neuron_outputs[29];
        end

        // Neuron 30
        if (NUM_NEURONS > 30) begin : neuron_30
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_30.mif"),
                .BiasFile     ("mp_node_b_0_1_30.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[30])
            );
            assign data_out_flat[30*DATA_BITS +: DATA_BITS] = neuron_outputs[30];
        end

        // Neuron 31
        if (NUM_NEURONS > 31) begin : neuron_31
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_0_1_31.mif"),
                .BiasFile     ("mp_node_b_0_1_31.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[31])
            );
            assign data_out_flat[31*DATA_BITS +: DATA_BITS] = neuron_outputs[31];
        end

    endgenerate
    
endmodule