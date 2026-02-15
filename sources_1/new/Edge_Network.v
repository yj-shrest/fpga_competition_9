`timescale 1ns / 1ps

// Fixed Edge_Network module - proper write pulse generation

module Edge_Network #( 
    parameter BLOCK_NUM = 0, 
    parameter DATA_BITS = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter RAM_ADDR_BITS_FOR_EDGE = 0,
    parameter NODE_FEATURES = 32,
    parameter EDGE_FEATURES = 32,
    parameter MAX_EDGES = 0

) (
    input clk,
    input rstn,
    input start,
    // Initial Edge Features from Edge Encoder
    input  [DATA_BITS*EDGE_FEATURES-1:0] initial_edge_features,
    output reg              initial_edge_features_re,
    input                   initial_edge_features_valid,
    // Current Edge features from the Edge PingPong 0 Buffer
    input  [DATA_BITS*EDGE_FEATURES-1:0] current_edge_features,
    output reg              current_edge_features_re,
    input                   current_edge_features_valid,
    output reg              current_edge_features_we,  // Changed to reg
    input                   current_edge_features_write_done,
    // Initial Node features from Node Encoder BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg              initial_node_features_re,
    input                   initial_node_features_valid,
    // Current Node features from the Node PingPong 0 Buffer
    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg              current_node_features_re,
    input                   current_node_features_valid,
    // Source Node index from Connectivity BRAMs
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] source_node_index,
    output reg                           source_node_index_re,
    input                                source_node_index_valid,
    // Destination Node index from Connectivity BRAMs
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] destination_node_index,
    output reg                           destination_node_index_re,
    input                                destination_node_index_valid,
    
    // Output Index for Edge Encoder BRAM (Same for Edge PingPong Buffer)
    output [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-6:0] edge_index,
    // Source Node Index for Scatter Sum In BRAM
    output [RAM_ADDR_BITS_FOR_NODE-1:0] in_node_index_ss,
    input                                in_node_ss_write_done,
    // Destination Node Index for Scatter Sum Out BRAM
    output [RAM_ADDR_BITS_FOR_NODE-1:0] out_node_index_ss,
    output reg                           scatter_sum_we,  // Changed to reg
    input                                out_node_ss_write_done,

    // Output Index for Node Encoder BRAM
    output reg [RAM_ADDR_BITS_FOR_NODE-1:0] node_index,
    // Output Edge Features to PingPong Buffer
    output reg [DATA_BITS*EDGE_FEATURES-1:0] edge_output,
    output reg              done
    );

    reg [RAM_ADDR_BITS_FOR_EDGE-1: 0] idx;
    reg [RAM_ADDR_BITS_FOR_NODE-1: 0] dest;
    reg [RAM_ADDR_BITS_FOR_NODE-1: 0] src;
    reg [DATA_BITS*NODE_FEATURES-1:0] initial_src_node_features;
    reg [DATA_BITS*NODE_FEATURES-1:0] initial_dest_node_features;
    reg [DATA_BITS*NODE_FEATURES-1:0] current_src_node_features;
    reg [DATA_BITS*NODE_FEATURES-1:0] current_dest_node_features;
    reg [DATA_BITS*EDGE_FEATURES-1:0] initial_edge_features_r;
    reg [DATA_BITS*EDGE_FEATURES-1:0] current_edge_features_r;
    reg [6*EDGE_FEATURES*DATA_BITS-1:0] concat_features;
    reg concat_features_valid;
    
    // Layer outputs - wires from modules
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer1_out;
    wire Layer1_out_valid;
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer2_out;
    wire Layer2_out_valid;
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer3_out;
    wire Layer3_out_valid;
    
    // Layer outputs - registered versions
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer1_out_r;
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer2_out_r;
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer3_out_r;
    reg current_edge_features_done_captured;
    reg in_node_ss_done_captured;
    reg out_node_ss_done_captured;
    
    reg [3:0] state, next_state;
    // FSM states
    localparam IDLE = 4'b0000,
               LOAD1 = 4'b0001,
               LOAD2 = 4'b0010,
               LOAD3 = 4'b0011,
               CONCAT = 4'b0100,
               LAYER1 = 4'b0101,
               LAYER2 = 4'b0110,
               LAYER3 = 4'b0111,
               STORE = 4'b1000,
               DONE = 4'b1001;
    reg layer1_start;
    reg layer2_start;
    reg layer3_start;

    // NEW: Track if writes have been initiated in STORE state
    reg store_writes_initiated;

    always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        current_edge_features_done_captured <= 1'b0;
        in_node_ss_done_captured <= 1'b0;
        out_node_ss_done_captured <= 1'b0;
    end else begin
        // Clear all captured flags when entering DONE state or starting new operation
        if (next_state == DONE || !store_writes_initiated) begin
            current_edge_features_done_captured <= 1'b0;
            in_node_ss_done_captured <= 1'b0;
            out_node_ss_done_captured <= 1'b0;
        end else begin
            // Capture each signal when it arrives (sticky bits)
            if (current_edge_features_write_done)
                current_edge_features_done_captured <= 1'b1;
            if (in_node_ss_write_done)
                in_node_ss_done_captured <= 1'b1;
            if (out_node_ss_write_done)
                out_node_ss_done_captured <= 1'b1;
        end
    end
end
    
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
    
    // Control layer start signals
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


    // Instantiate Edge Message Passing Layers with block-specific modules
    generate
        case (BLOCK_NUM)
    0: begin : block_0_layers
        MP_Edge_Layer_B0_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B0_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B0_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B1_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );
        
        MP_Edge_Layer_B1_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B1_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B2_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B2_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B2_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B3_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B3_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B3_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B4_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B4_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B4_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B5_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B5_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B5_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B6_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B6_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B6_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
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
        MP_Edge_Layer_B7_L1 #(
            .LAYER_NO(1),
            .NUM_NEURONS(32),
            .NUM_FEATURES(192),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_1_inst (
            .clk(clk),
            .rstn(layer1_start),
            .activation_function(1'b1),
            .start(layer1_start),
            .data_in_flat(concat_features),
            .data_out_flat(Layer1_out),
            .done(Layer1_out_valid)
        );

        MP_Edge_Layer_B7_L2 #(
            .LAYER_NO(2),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_2_inst (
            .clk(clk),
            .rstn(layer2_start),
            .activation_function(1'b1),
            .start(layer2_start),
            .data_in_flat(Layer1_out_r),
            .data_out_flat(Layer2_out),
            .done(Layer2_out_valid)
        );

        MP_Edge_Layer_B7_L3 #(
            .LAYER_NO(3),
            .NUM_NEURONS(32),
            .NUM_FEATURES(32),
            .DATA_BITS(8),
            .WEIGHT_BITS(8),
            .BIAS_BITS(8)
        ) mp_edge_layer_3_inst (
            .clk(clk),
            .rstn(layer3_start),
            .activation_function(1'b1),
            .start(layer3_start),
            .data_in_flat(Layer2_out_r),
            .data_out_flat(Layer3_out),
            .done(Layer3_out_valid)
        );
    end

    default: begin : block_default
        // Synthesis tools will eliminate this branch if BLOCK_NUM is constant
        initial begin
            $display("ERROR: Invalid BLOCK_NUM = %d in Edge_Network", BLOCK_NUM);
            $finish;
        end
    end
endcase
    endgenerate

    // Index management
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            idx <= 0;
        end 
        else if (state == DONE) begin
            if (idx < MAX_EDGES - 1)
                idx <= idx + 1;  // Process next edge
            else
                idx <= 0;        // Reset for next round
        end
    end

    assign edge_index = idx;
    assign edge_address = idx*EDGE_FEATURES;
    assign out_node_index_ss = src*NODE_FEATURES;
    assign in_node_index_ss = dest*NODE_FEATURES;

    // State register
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = LOAD1;
            end

            LOAD1: begin
                if (initial_edge_features_valid && 
                    current_edge_features_valid &&
                    source_node_index_valid &&
                    destination_node_index_valid
                    )
                    next_state = LOAD2;
            end

            LOAD2: begin
                if (initial_node_features_valid &&
                    current_node_features_valid
                    )
                    next_state = LOAD3;
            end

            LOAD3: begin
                if (initial_node_features_valid &&
                    current_node_features_valid
                    )
                    next_state = CONCAT;
            end

            CONCAT: begin
                if (concat_features_valid)
                    next_state = LAYER1;
            end

            LAYER1: begin
                if (Layer1_out_valid) begin
                    $display("[%0t] valid- %b", $time, Layer1_out_valid);
                    next_state = LAYER2;
                end
            end

            LAYER2: begin
                if (Layer2_out_valid)
                    next_state = LAYER3;
            end

            LAYER3: begin
                if (Layer3_out_valid)
                    next_state = STORE;
            end

            STORE: begin
             edge_output = Layer3_out_r;  // Use registered version
                if (store_writes_initiated && 
                    (current_edge_features_done_captured) &&
                    (in_node_ss_done_captured) &&
                    (out_node_ss_done_captured))
                    next_state = DONE;
            end

            DONE: begin
                if (idx < MAX_EDGES - 1)
                    next_state = LOAD1;  // Auto-restart for next edge
                else
                    next_state = IDLE;   // All edges processed
            end

            default: next_state = IDLE;
        endcase
    end
    
    reg load1_read_done;
    reg load2_read_done;
    reg load3_read_done;

    // Reset the flag
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            load1_read_done <= 0;
            load2_read_done <= 0;
            load3_read_done <= 0;
        end
        else if (state == IDLE) begin
            load1_read_done <= 0;
            load2_read_done <= 0;
            load3_read_done <= 0;
        end 
        else if (state == LOAD1 && !load1_read_done) begin
            load1_read_done <= 1;
            load2_read_done <= 0;
            load3_read_done <= 0;
        end
        else if (state == LOAD2 && !load2_read_done) begin
            load2_read_done <= 1;
            load3_read_done <= 0;
            load1_read_done <= 0;
        end
        else if (state == LOAD3 && !load3_read_done) begin
            load3_read_done <= 1;
            load1_read_done <= 0;
            load2_read_done <= 0;
        end
    end
    
    // NEW: Track when write pulses have been generated in STORE state
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            store_writes_initiated <= 0;
        else if (state != STORE)
            store_writes_initiated <= 0;
        else if (state == STORE && !store_writes_initiated)
            store_writes_initiated <= 1;  // Set on first cycle in STORE
    end
    
    /* =========================
       OUTPUT / CONTROL LOGIC
       (MOORE FSM) - MODIFIED FOR SINGLE-CYCLE WRITE PULSES
    ========================== */
    always @(*) begin
        // ---- defaults ----
        initial_edge_features_re     = 0;
        current_edge_features_re     = 0;
        initial_node_features_re     = 0;
        current_node_features_re     = 0;
        source_node_index_re         = 0;
        destination_node_index_re    = 0;

        current_edge_features_we     = 0;
        scatter_sum_we               = 0;

        node_index                   = 0;
        done                         = 0;

        case (state)
            LOAD1: begin
                if (!load1_read_done) begin
                    initial_edge_features_re   = 1;
                    current_edge_features_re   = 1;
                    source_node_index_re       = 1;
                    destination_node_index_re  = 1;
                end
            end

            LOAD2: begin
                if (!load2_read_done) begin 
                    node_index = src*NODE_FEATURES;
                    initial_node_features_re   = 1;
                    current_node_features_re = 1;
                end
            end

            LOAD3: begin
                if (!load3_read_done) begin
                    node_index = dest*NODE_FEATURES;
                    initial_node_features_re   = 1;
                    current_node_features_re = 1;
                end
            end

            STORE: begin
                // FIXED: Only assert write enables on first cycle in STORE state
                if (!store_writes_initiated) begin
                    current_edge_features_we = 1;
                    scatter_sum_we = 1;
                end
            end

            DONE: begin
                // Only assert done when all edges are processed
                if (idx >= MAX_EDGES - 1)
                    done = 1;
            end
        endcase
    end

    // ALTERNATIVE IMPLEMENTATION: Using registered outputs
    // If the above combinational approach doesn't work well with your timing,
    // you can use this registered version instead:
    /*
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_edge_features_we <= 0;
            scatter_sum_we <= 0;
        end else begin
            // Default: clear write enables
            current_edge_features_we <= 0;
            scatter_sum_we <= 0;
            
            // Generate single-cycle pulse when entering STORE state
            if (state != STORE && next_state == STORE) begin
                current_edge_features_we <= 1;
                scatter_sum_we <= 1;
            end
        end
    end
    */

    /* =========================
       DATAPATH REGISTERS
    ========================== */
    always @(posedge clk) begin
        case (state)
            LOAD1: begin
                initial_edge_features_r <= initial_edge_features;
                current_edge_features_r <= current_edge_features;
                src                 <= source_node_index;
                dest                <= destination_node_index;
            end

            LOAD2: begin
                initial_src_node_features <= initial_node_features;
                current_src_node_features <= current_node_features;
            end

            LOAD3: begin
                initial_dest_node_features <= initial_node_features;
                current_dest_node_features <= current_node_features;
            end

            CONCAT: begin
                concat_features <= {
                    current_edge_features_r,
                    initial_edge_features_r,
                    current_src_node_features,
                    initial_src_node_features,
                    current_dest_node_features,
                    initial_dest_node_features
                };
                $display("Edge Network Block %d - CONCAT Features: %h", BLOCK_NUM, concat_features);
                $display("Edge Network Block %d - current edge features : %h", BLOCK_NUM, current_edge_features_r);
                $display("Edge Network Block %d - initial edge features : %h", BLOCK_NUM, initial_edge_features_r);
                $display("Edge Network Block %d - current src node features : %h", BLOCK_NUM, current_src_node_features);
                $display("Edge Network Block %d - initial src node features : %h", BLOCK_NUM, initial_src_node_features);
                $display("Edge Network Block %d - current dest node features : %h", BLOCK_NUM, current_dest_node_features);
                $display("Edge Network Block %d - initial dest node features : %h", BLOCK_NUM, initial_dest_node_features);
            end

            LAYER1: begin
                // $display("Edge Network Block %d - Layer 1 Input: %h", BLOCK_NUM, concat_features);
                if (Layer1_out_valid)
                    $display("Edge Network Block %d - Layer 1 Output: %h", BLOCK_NUM, Layer1_out_r);
            end
            LAYER2: begin
                // $display("Edge Network Block %d - Layer 2 Input: %h", BLOCK_NUM, Layer1_out_r);
                if (Layer2_out_valid)
                    $display("Edge Network Block %d - Layer 2 Output: %h", BLOCK_NUM, Layer2_out_r);
            end
            LAYER3: begin
                // $display("Edge Network Block %d - Layer 3 Input: %h", BLOCK_NUM, Layer2_out_r);
                if (Layer3_out_valid)
                    $display("Edge Network Block %d - Layer 3 Output: %h", BLOCK_NUM, Layer3_out_r);
            end
            STORE: begin
                if (!store_writes_initiated)
                    $display("Edge Network Block %d -Edge %d, Layer 3 Output (to be stored): %h", BLOCK_NUM, edge_index, Layer3_out_r);
            end
        endcase
    end

    reg layer_reset;

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            layer_reset <= 0;
        else if (state == CONCAT && concat_features_valid)
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
            concat_features_valid <= 1;
        else if (state != CONCAT)
            concat_features_valid <= 0;
    end

endmodule