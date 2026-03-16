`timescale 1ns / 1ps

module node_encoder
#(
    parameter NUM_NODES      = 8,            // Example: 8 nodes
    parameter NUM_FEATURES   = 12,           // 12 features per node
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8,
    parameter ADDR_BITS      = 14,
    parameter OUT_FEATURES   = 32,
    parameter MEM_FILE       = "node_initial_features.mem"
)
(
    input  clk,
    input  rstn,
    input  start,
    
    // Optional: Output the encoded results
    output reg [OUT_FEATURES*DATA_BITS-1:0] encoded_data,
    output reg [ADDR_BITS-1:0] node_addr_out,
    output reg data_valid,
    
    output reg done
);

    //============================================
    // FSM States
    //============================================
    localparam [2:0] IDLE        = 3'b000,
                     READ_NODE   = 3'b001,
                     LAYER1      = 3'b010,
                     LAYER2      = 3'b011,
                     LAYER3      = 3'b100,
                     WRITE       = 3'b101,
                     NEXT_NODE   = 3'b110,
                     FINISH      = 3'b111;
    
    reg [2:0] state, next_state;
    reg [ADDR_BITS-1:0] node_idx;
    reg process_complete;
    
    //============================================
    // Internal Node Memory (stores 96-bit values = 12 × 8 bits)
    //============================================
    reg [NUM_FEATURES*DATA_BITS-1:0] node_mem [0:NUM_NODES-1];
    reg [NUM_FEATURES*DATA_BITS-1:0] current_node_data;
    
    //============================================
    // Layer Interconnections
    //============================================
    reg layer1_rstn;
    wire [NUM_FEATURES*DATA_BITS-1:0] layer1_in;
    wire [OUT_FEATURES*DATA_BITS-1:0] layer1_out;
    wire layer1_done;
    
    reg layer2_rstn;
    wire [OUT_FEATURES*DATA_BITS-1:0] layer2_out;
    wire layer2_done;
    
    reg layer3_rstn;
    wire [OUT_FEATURES*DATA_BITS-1:0] layer3_out;
    wire layer3_done;
    
    // Data registers
    reg [OUT_FEATURES*DATA_BITS-1:0] layer1_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] layer2_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] encoded_features_reg;
    
    //============================================
    // Instantiate Layer 1
    //============================================
    node_encoder_layer_1 #(
        .LAYER_NO      (1),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer1_inst (
        .clk                 (clk),
        .rstn                (layer1_rstn),
        .activation_function (1'b1),  // ReLU
        .data_in_flat        (layer1_in),
        .data_out_flat       (layer1_out),
        .valid_out                (layer1_done)
    );
    
    //============================================
    // Instantiate Layer 2
    //============================================
    node_encoder_layer_2 #(
        .LAYER_NO      (2),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer2_inst (
        .clk                 (clk),
        .rstn                (layer2_rstn),
        .activation_function (1'b1),  // ReLU
        .data_in_flat        (layer1_out_reg),
        .data_out_flat       (layer2_out),
        .valid_out                (layer2_done)
    );
    
    //============================================
    // Instantiate Layer 3
    //============================================
    node_encoder_layer_3 #(
        .LAYER_NO      (3),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer3_inst (
        .clk                 (clk),
        .rstn                (layer3_rstn),
        .activation_function (1'b1),  // ReLU
        .data_in_flat        (layer2_out_reg),
        .data_out_flat       (layer3_out),
        .valid_out                (layer3_done)
    );
    
    //============================================
    // Layer 1 Input Assignment
    //============================================
    assign layer1_in = current_node_data;
    reg [DATA_BITS-1:0] temp_array [0:(NUM_NODES*NUM_FEATURES)-1];
    initial begin
    $readmemb(MEM_FILE, temp_array);
end
    //============================================
    // Initialize Memory from File
    //============================================
    genvar j;
generate
    for (j = 0; j < NUM_NODES; j = j + 1) begin
        // Continuous assignment or always block for each node
        always @(*) begin
            node_mem[j] = {
                temp_array[(j*6)+5], temp_array[(j*6)+4], temp_array[(j*6)+3],
                temp_array[(j*6)+2], temp_array[(j*6)+1], temp_array[(j*6)+0]
            };
        end
    end
endgenerate
    
    //============================================
    // State Register
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //============================================
    // Next State Logic
    //============================================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start)
                    next_state = READ_NODE;
            end
            
            READ_NODE: begin
                next_state = LAYER1;
            end
            
            LAYER1: begin
                if (layer1_done)
                    next_state = LAYER2;
            end
            
            LAYER2: begin
                if (layer2_done)
                    next_state = LAYER3;
            end
            
            LAYER3: begin
                if (layer3_done)
                    next_state = WRITE;
            end
            
            WRITE: begin
                next_state = NEXT_NODE;
            end
            
            NEXT_NODE: begin
                if (node_idx >= NUM_NODES - 1)  // Last node completed
                    next_state = FINISH;
                else
                    next_state = READ_NODE;     // Process next node
            end
            
            FINISH: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    //============================================
    // Node Index Counter
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            node_idx <= 0;
            process_complete <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        node_idx <= 0;
                        process_complete <= 0;
                    end
                end

                NEXT_NODE: begin
                    if (node_idx < NUM_NODES - 1) begin
                        node_idx <= node_idx + 1;  // Increment only if not last node
                    end
                end
                
                FINISH: begin
                    process_complete <= 1;  // Set complete flag in FINISH state
                    node_idx <= 0;          // Reset index
                end
                
                default: ;
            endcase
        end
    end
    
    //============================================
    // Output Logic
    //============================================
    always @(*) begin
        done = 0;
        encoded_data = 0;
        node_addr_out = 0;
        data_valid = 0;
        
        case (state)
            WRITE: begin
                encoded_data = encoded_features_reg;
                node_addr_out = node_idx;
                data_valid = 1;
            end
            
            FINISH: begin
                done = 1;  // Assert done in FINISH state
            end
            
            default: ;
        endcase
    end
    
    //============================================
    // Layer Reset Control
    //============================================
    always @(*) begin
        layer1_rstn = 0;
        layer2_rstn = 0;
        layer3_rstn = 0;
        
        case (state)
            LAYER1: layer1_rstn = rstn;
            LAYER2: layer2_rstn = rstn;
            LAYER3: layer3_rstn = rstn;
            default: ;
        endcase
    end
    
    //============================================
    // Data Path Registers
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_node_data <= 0;
            layer1_out_reg <= 0;
            layer2_out_reg <= 0;
            encoded_features_reg <= 0;
        end else begin
            case (state)
                READ_NODE: begin
                    // Read node data from internal memory
                    current_node_data <= node_mem[node_idx];
                    // $display("=== Processing Node %0d: Input = %h ===", 
                            // node_idx, node_mem[node_idx]);
                end
                
                LAYER1: begin
                    if (layer1_done) begin
                        layer1_out_reg <= layer1_out;
                        // $display("  Layer1 Output: %h", layer1_out);
                    end
                end
                
                LAYER2: begin
                    if (layer2_done) begin
                        layer2_out_reg <= layer2_out;
                        // $display("  Layer2 Output: %h", layer2_out);
                    end
                end
                
                LAYER3: begin
                    if (layer3_done) begin
                        encoded_features_reg <= layer3_out;
                        // $display("  Layer3 Output (Encoded): %h", layer3_out);
                        // $display("=== Node %0d Processing Complete ===", node_idx);
                    end
                end
                
                FINISH: begin
                    // $display("========================================");
                    // $display("ALL %0d NODES PROCESSED COMPLETELY", NUM_NODES);
                    // $display("========================================");
                end
                
                default: ;
            endcase
        end
    end
    
    //============================================
    // Debug Display
    //============================================
    initial begin
        // $display("========================================");
        // $display("Node Encoder with Internal Memory Load");
        // $display("  Memory File:        %s", MEM_FILE);
        // $display("  Number of Nodes:    %0d", NUM_NODES);
        // $display("  Features per Node:  %0d", NUM_FEATURES);
        // $display("  Total bits/node:    %0d bits", NUM_FEATURES * DATA_BITS);
        // $display("  3-Layer Architecture:");
        // $display("    Layer 1: %0d -> %0d", NUM_FEATURES, OUT_FEATURES);
        // $display("    Layer 2: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("    Layer 3: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("========================================");
    end

endmodule