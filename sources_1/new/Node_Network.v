`timescale 1ns / 1ps

// Node_Network module
// Processes node features by concatenating scatter-sum features and current/initial node features

module Node_Network #(
    parameter BLOCK_NUM = 0, 
    parameter DATA_BITS = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter NODE_FEATURES = 32,
    parameter MAX_NODES = 0

) (
    input clk,
    input rstn,
    input start,
    
    // Scatter Sum In features from Scatter Sum In BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_in,
    output reg                           scatter_sum_features_in_re,
    input                                scatter_sum_features_in_valid,
    
    // Scatter Sum Out features from Scatter Sum Out BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_out,
    output reg                           scatter_sum_features_out_re,
    input                                scatter_sum_features_out_valid,
    
    // Current Node features from the Node PingPong 0 Buffer
    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg                           current_node_features_re,
    input                                current_node_features_valid,
    output reg                           current_node_features_we,
    input                                current_node_features_write_done,
    
    // Initial Node features from Node Encoder BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg                           initial_node_features_re,
    input                                initial_node_features_valid,
    
    // Output Index for Node Encoder BRAM (Same for Node PingPong Buffer and Scatter Sum)
    output [RAM_ADDR_BITS_FOR_NODE-1:0] node_address,
    output [RAM_ADDR_BITS_FOR_NODE-6:0] node_index,
    
    // Output Node Features to PingPong Buffer
    output [DATA_BITS*NODE_FEATURES-1:0] node_output,
    output reg                           done
);

    reg [RAM_ADDR_BITS_FOR_NODE-1:0] idx;
    reg [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_in_reg;
    reg [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_out_reg;
    reg [DATA_BITS*NODE_FEATURES-1:0] current_node_features_reg;
    reg [DATA_BITS*NODE_FEATURES-1:0] initial_node_features_reg;
    reg [4*NODE_FEATURES*DATA_BITS-1:0] concat_features;
    reg concat_features_valid;
    
    // Layer outputs - wires from modules
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer1_out;
    wire Layer1_out_valid;
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer2_out;
    wire Layer2_out_valid;
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer3_out;
    wire Layer3_out_valid;
    
    // Layer outputs - registered versions
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer1_out_r;
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer2_out_r;
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer3_out_r;

    // FSM states
    localparam IDLE = 4'b0000,
               LOAD1 = 4'b0001,
               CONCAT = 4'b0010,
               LAYER1 = 4'b0011,
               LAYER2 = 4'b0100,
               LAYER3 = 4'b0101,
               STORE = 4'b0110,
               DONE = 4'b0111;
    
    reg [3:0] state, next_state;
    reg layer1_start;
    reg layer2_start;
    reg layer3_start;

    
    // Capture layer outputs when valid
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            Layer1_out_r <= 0;
            Layer2_out_r <= 0;
            Layer3_out_r <= 0;
        end else begin
            if (Layer1_out_valid)
                Layer1_out_r <= Layer1_out;
            if (Layer2_out_valid)
                Layer2_out_r <= Layer2_out;
            if (Layer3_out_valid)
                Layer3_out_r <= Layer3_out;
        end
    end
     always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            layer1_start <= 0;
            layer2_start <= 0;
            layer3_start <= 0;
        end else begin
            // Start layer 1 when entering LAYER1 state
            if (state == LAYER1 && !Layer1_out_valid) begin
                layer1_start <= 1;
            end else begin
                layer1_start <= 0;
            end
            
            // Start layer 2 when entering LAYER2 state
            if (state == LAYER2 && !Layer2_out_valid) begin
                layer2_start <= 1;
            end else begin
                layer2_start <= 0;
            end
            
            // Start layer 3 when entering LAYER3 state
            if (state == LAYER3 && !Layer3_out_valid) begin
                layer3_start <= 1;
            end else begin
                layer3_start <= 0;
            end
        end
    end
    
    // Instantiate Node Message Passing Layers with block-specific modules
    generate
        case (BLOCK_NUM)
            0: begin : block_0_layers
                MP_Node_Layer_B0_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B0_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B0_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            1: begin : block_1_layers
                MP_Node_Layer_B1_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B1_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B1_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            2: begin : block_2_layers
                MP_Node_Layer_B2_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B2_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B2_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            3: begin : block_3_layers
                MP_Node_Layer_B3_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B3_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B3_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            4: begin : block_4_layers
                MP_Node_Layer_B4_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B4_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B4_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            5: begin : block_5_layers
                MP_Node_Layer_B5_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B5_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B5_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            6: begin : block_6_layers
                MP_Node_Layer_B6_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B6_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B6_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end

            7: begin : block_7_layers
                MP_Node_Layer_B7_L1 #(
                    .LAYER_NO(1),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(128),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_1_inst (
                    .clk(clk),
                    .rstn(layer1_start),
                    .activation_function(1'b1),
                    .start(layer1_start),
                    .data_in_flat(concat_features),
                    .data_out_flat(Layer1_out),
                    .done(Layer1_out_valid)
                );

                MP_Node_Layer_B7_L2 #(
                    .LAYER_NO(2),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_2_inst (
                    .clk(clk),
                    .rstn(layer2_start),
                    .activation_function(1'b1),
                    .start(layer2_start),
                    .data_in_flat(Layer1_out_r),
                    .data_out_flat(Layer2_out),
                    .done(Layer2_out_valid)
                );

                MP_Node_Layer_B7_L3 #(
                    .LAYER_NO(3),
                    .NUM_NEURONS(32),
                    .NUM_FEATURES(32),
                    .DATA_BITS(8),
                    .WEIGHT_BITS(8),
                    .BIAS_BITS(8)
                ) mp_node_layer_3_inst (
                    .clk(clk),
                    .rstn(layer3_start),
                    .activation_function(1'b1),
                    .start(layer3_start),
                    .data_in_flat(Layer2_out_r),
                    .data_out_flat(Layer3_out),
                    .done(Layer3_out_valid)
                );
            end
        endcase
    endgenerate

    // Assign outputs - use registered version
    assign node_output = Layer3_out_r;
    assign node_address = idx * NODE_FEATURES;
    assign node_index = idx*NODE_FEATURES;

    /* =========================
       STATE REGISTER
    ========================== */
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            idx <= 0;
        end else begin
            if (state != next_state) begin
                // $display("[%0t] Node Network FSM: %s -> %s (idx=%0d)", $time, 
                //     state == IDLE ? "IDLE" :
                //     state == LOAD1 ? "LOAD1" :
                //     state == CONCAT ? "CONCAT" :
                //     state == LAYER1 ? "LAYER1" :
                //     state == LAYER2 ? "LAYER2" :
                //     state == LAYER3 ? "LAYER3" :
                //     state == STORE ? "STORE" :
                //     state == DONE ? "DONE" : "UNKNOWN",
                //     next_state == IDLE ? "IDLE" :
                //     next_state == LOAD1 ? "LOAD1" :
                //     next_state == CONCAT ? "CONCAT" :
                //     next_state == LAYER1 ? "LAYER1" :
                //     next_state == LAYER2 ? "LAYER2" :
                //     next_state == LAYER3 ? "LAYER3" :
                //     next_state == STORE ? "STORE" :
                //     next_state == DONE ? "DONE" : "UNKNOWN",
                //     idx);
            end
            state <= next_state;
            
            // Increment idx when transitioning from DONE to LOAD1 for next node
            if (state == DONE && next_state == LOAD1) begin
                // $display("[%0t] Node Network: Incrementing idx from %0d to %0d", $time, idx, idx+1);
                idx <= idx + 1;
            end else if (state == IDLE && next_state == LOAD1) begin
                idx <= 0;  // Reset on first start
            end
        end
    end

    /* =========================
       NEXT STATE LOGIC
       (MEALY FSM)
    ========================== */
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start)
                    next_state = LOAD1;
            end

            LOAD1: begin
                if (scatter_sum_features_in_valid && 
                    scatter_sum_features_out_valid && 
                    current_node_features_valid && 
                    initial_node_features_valid) begin
                    // $display("[%0t] Node Network LOAD1: All data valid for node %0d", $time, idx);
                    next_state = CONCAT;
                end else begin
                    if (!scatter_sum_features_in_valid || !scatter_sum_features_out_valid || 
                        !current_node_features_valid || !initial_node_features_valid) begin
                        // $display("[%0t] Node Network LOAD1: Waiting for data (ss_in=%b, ss_out=%b, curr=%b, init=%b)",
                        //     $time, scatter_sum_features_in_valid, scatter_sum_features_out_valid,
                        //     current_node_features_valid, initial_node_features_valid);
                    end
                end
            end

            CONCAT: begin
                if (concat_features_valid) begin
                    // $display("[%0t] Node Network CONCAT: Features concatenated for node %0d", $time, idx);
                    next_state = LAYER1;
                end
            end

            LAYER1: begin
                if (Layer1_out_valid) begin
                    // $display("[%0t] Node Network Layer1 valid - %b", $time, Layer1_out_valid);
                    next_state = LAYER2;
                end
            end

            LAYER2: begin
                if (Layer2_out_valid)
                    next_state = LAYER3;
            end

            LAYER3: begin
                if (Layer3_out_valid) begin
                    // $display("[%0t] Node Network: Layer3_out_valid detected, transitioning to STORE", $time);
                    next_state = STORE;
                end
            end

            STORE: begin
                if (current_node_features_write_done)
                    next_state = DONE;
            end

            DONE: begin
                if (idx < MAX_NODES - 1) begin
                    // $display("[%0t] Node Network DONE: Node %0d complete (idx=%0d < MAX_NODES-1=%0d), proceeding to node %0d", 
                    //     $time, idx, idx, MAX_NODES-1, idx+1);
                    next_state = LOAD1;  // Auto-restart for next node
                end else begin
                    // $display("[%0t] Node Network DONE: All nodes complete (idx=%0d >= MAX_NODES-1=%0d)", 
                        // $time, idx, MAX_NODES-1);
                    next_state = IDLE;   // All nodes processed
                end
            end

            default: next_state = IDLE;
        endcase
    end
    
    reg load1_read_done;

    // Reset the flag
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            load1_read_done <= 0;
        end
        else if (state == IDLE || state == DONE) begin
            // Reset when idle or when transitioning from DONE to LOAD1 for next node
            load1_read_done <= 0;
        end 
        else if (state == LOAD1 && !load1_read_done) begin
            load1_read_done <= 1;
        end
    end
    
    /* =========================
       OUTPUT / CONTROL LOGIC
       (MOORE FSM)
    ========================== */
    always @(*) begin
        // ---- defaults ----
        scatter_sum_features_in_re   = 0;
        scatter_sum_features_out_re  = 0;
        current_node_features_re     = 0;
        initial_node_features_re     = 0;
        current_node_features_we     = 0;
        done                         = 0;

        case (state)
            LOAD1: begin
                if (!load1_read_done) begin
                    scatter_sum_features_in_re  = 1;
                    scatter_sum_features_out_re = 1;
                    current_node_features_re    = 1;
                    initial_node_features_re    = 1;
                    // $display("[%0t] Node Network LOAD1: Requesting data for node %0d (addr=%0d)", $time, idx, idx * NODE_FEATURES);
                end
            end

            STORE: begin
                current_node_features_we = 1;
            end

            DONE: begin
                // Only assert done when all nodes are processed
                if (idx >= MAX_NODES - 1)
                    done = 1;
            end
        endcase
    end

    /* =========================
       DATAPATH REGISTERS
    ========================== */
    always @(posedge clk) begin
        case (state)
            LOAD1: begin
                scatter_sum_features_in_reg  <= scatter_sum_features_in;
                scatter_sum_features_out_reg <= scatter_sum_features_out;
                current_node_features_reg    <= current_node_features;
                initial_node_features_reg    <= initial_node_features;
            end

            CONCAT: begin
                concat_features <= {
                    scatter_sum_features_in_reg,
                    scatter_sum_features_out_reg,
                    current_node_features_reg,
                    initial_node_features_reg
                };
                // $display("Node Network Block %d - CONCAT Features: %h", BLOCK_NUM, concat_features);
                // $display("Node Network Block %d - scatter_sum_in: %h", BLOCK_NUM, scatter_sum_features_in_reg);
                // $display("Node Network Block %d - scatter_sum_out: %h", BLOCK_NUM, scatter_sum_features_out_reg);
                // $display("Node Network Block %d - current node features: %h", BLOCK_NUM, current_node_features_reg);
                // $display("Node Network Block %d - initial node features: %h", BLOCK_NUM, initial_node_features_reg);
            end

            // LAYER1: begin
            //     // $display("Node Network Block %d - Layer 1 Input: %h", BLOCK_NUM, concat_features);
            //     if (Layer1_out_valid)
            //         // $display("Node Network Block %d - Layer 1 Output: %h", BLOCK_NUM, Layer1_out_r);
            // end
            
            // LAYER2: begin
            //     // $display("Node Network Block %d - Layer 2 Input: %h", BLOCK_NUM, Layer1_out_r);
            //     if (Layer2_out_valid)
            //         // $display("Node Network Block %d - Layer 2 Output: %h", BLOCK_NUM, Layer2_out_r);
            // end
            
            // LAYER3: begin
            //     // $display("Node Network Block %d - Layer 3 Input: %h", BLOCK_NUM, Layer2_out_r);
            //     if (Layer3_out_valid)
            //         // $display("Node Network Block %d - Layer 3 Output: %h", BLOCK_NUM, Layer3_out_r);
            // end
            
            // STORE: begin
            //     // $display("Node Network Block %d - Layer 3 Output (to be stored): %h", BLOCK_NUM, Layer3_out_r);
            // end
        endcase
    end

    reg layer_reset;

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            layer_reset <= 0;
        else if (state == CONCAT && concat_features_valid)
            // Reset layers when valid data is ready (pulse for 1 cycle)
            layer_reset <= 1;
        else
            layer_reset <= 0;
    end

    // Generate concat_features_valid one cycle AFTER entering CONCAT state
    reg concat_state_d;

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            concat_state_d <= 0;
        else
            concat_state_d <= (state == CONCAT);
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            concat_features_valid <= 0;
        else if (state == CONCAT && !concat_state_d)
            // First cycle in CONCAT state - assert valid after data is registered
            concat_features_valid <= 1;
        else if (state != CONCAT)
            // Clear valid when leaving CONCAT state
            concat_features_valid <= 0;
    end

endmodule