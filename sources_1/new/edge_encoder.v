`timescale 1ns / 1ps

module edge_encoder
#(
    parameter NUM_EDGES      = 4,
    parameter NUM_FEATURES   = 6,
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8,
    parameter ADDR_BITS      = 14,
    parameter OUT_FEATURES   = 32,
    parameter MEM_FILE       = "edge_initial_features.mem"
)
(
    input  clk,
    input  rstn,
    input  start,
    
    // Optional: Output the encoded results
    output reg [OUT_FEATURES*DATA_BITS-1:0] encoded_data,
    output reg [ADDR_BITS-1:0] edge_addr_out,
    output reg data_valid,
    
    output reg done
);

    //============================================
    // FSM States
    //============================================
    localparam [2:0] IDLE        = 3'b000,
                     READ_EDGE   = 3'b001,
                     LAYER1      = 3'b010,
                     LAYER2      = 3'b011,
                     LAYER3      = 3'b100,
                     WRITE       = 3'b101,
                     NEXT_EDGE   = 3'b110,
                     FINISH      = 3'b111;  // Added FINISH state
    
    reg [2:0] state, next_state;
    reg [ADDR_BITS-1:0] edge_idx;
    reg process_complete;
    
    //============================================
    // Internal Edge Memory
    //============================================
    reg [NUM_FEATURES*DATA_BITS-1:0] edge_mem [0:NUM_EDGES-1];
    reg [NUM_FEATURES*DATA_BITS-1:0] current_edge_data;
    
    //============================================
    // Buffer for reading individual bytes from file
    //============================================
    reg [DATA_BITS-1:0] byte_buffer [0:NUM_FEATURES-1];
    reg [DATA_BITS-1:0] byte_value;
    
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
    edge_encoder_layer_1 #(
        .LAYER_NO      (1),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer1_inst (
        .clk                 (clk),
        .rstn                (layer1_rstn),
        .activation_function (1'b1),
        .data_in_flat        (layer1_in),
        .data_out_flat       (layer1_out),
        .done                (layer1_done)
    );
    
    //============================================
    // Instantiate Layer 2
    //============================================
    edge_encoder_layer_2 #(
        .LAYER_NO      (2),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer2_inst (
        .clk                 (clk),
        .rstn                (layer2_rstn),
        .activation_function (1'b1),
        .data_in_flat        (layer1_out_reg),
        .data_out_flat       (layer2_out),
        .done                (layer2_done)
    );
    
    //============================================
    // Instantiate Layer 3
    //============================================
    edge_encoder_layer_3 #(
        .LAYER_NO      (3),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer3_inst (
        .clk                 (clk),
        .rstn                (layer3_rstn),
        .activation_function (1'b1),
        .data_in_flat        (layer2_out_reg),
        .data_out_flat       (layer3_out),
        .done                (layer3_done)
    );
    
    //============================================
    // Layer 1 Input Assignment
    //============================================
    assign layer1_in = current_edge_data;
    reg [DATA_BITS-1:0] temp_array [0:(NUM_EDGES*NUM_FEATURES)-1];
    integer j;
    //============================================
    // Initialize Memory from File
    //============================================
    initial begin
        
        
        $display("========================================");
        $display("Loading edge features from: %s", MEM_FILE);
        $display("========================================");
        
        // Use $readmemh with a temporary array
        begin
            
            $readmemb(MEM_FILE, temp_array);
            
            for (j = 0; j < NUM_EDGES; j = j + 1) begin
                edge_mem[j] = {
                    temp_array[(j*6)+5], temp_array[(j*6)+4], temp_array[(j*6)+3],
                    temp_array[(j*6)+2], temp_array[(j*6)+1], temp_array[(j*6)+0]
                };
                $display("Edge %0d: %h", j, edge_mem[j]);
            end
        end
        
        $display("Total edges loaded: %0d", NUM_EDGES);
        $display("========================================");
    end
    
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
    // Next State Logic - FIXED
    //============================================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start)
                    next_state = READ_EDGE;
            end
            
            READ_EDGE: begin
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
                next_state = NEXT_EDGE;
            end
            
            NEXT_EDGE: begin
                if (edge_idx >= NUM_EDGES - 1)  // Last edge completed
                    next_state = FINISH;
                else
                    next_state = READ_EDGE;     // Process next edge
            end
            
            FINISH: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    //============================================
    // Edge Index Counter - FIXED
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            edge_idx <= 0;
            process_complete <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        edge_idx <= 0;
                        process_complete <= 0;
                    end
                end

                NEXT_EDGE: begin
                    if (edge_idx < NUM_EDGES - 1) begin
                        edge_idx <= edge_idx + 1;  // Increment only if not last edge
                    end
                end
                
                FINISH: begin
                    process_complete <= 1;  // Set complete flag in FINISH state
                    edge_idx <= 0;          // Reset index
                end
                
                default: ;
            endcase
        end
    end
    
    //============================================
    // Output Logic - FIXED
    //============================================
    always @(*) begin
        done = 0;
        encoded_data = 0;
        edge_addr_out = 0;
        data_valid = 0;
        
        case (state)
            WRITE: begin
                encoded_data = encoded_features_reg;
                edge_addr_out = edge_idx; 
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
            current_edge_data <= 0;
            layer1_out_reg <= 0;
            layer2_out_reg <= 0;
            encoded_features_reg <= 0;
        end else begin
            case (state)
                READ_EDGE: begin
                    // Read edge data from internal memory
                    current_edge_data <= edge_mem[edge_idx];
                    // $display("=== Processing Edge %0d: Input = %h ===", 
//                            edge_idx, edge_mem[edge_idx]);
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
                        // $display("=== Edge %0d Processing Complete ===", edge_idx);
                    end
                end
                
                FINISH: begin
                    // $display("========================================");
                    // $display("ALL %0d EDGES PROCESSED COMPLETELY", NUM_EDGES);
                    // $display("========================================");
                end
                
                default: ;
            endcase
        end
    end
    
    //============================================
    // Debug Display
    //============================================
    // initial begin
        // $display("========================================");
        // $display("Edge Encoder with Internal Memory Load");
        // $display("  Memory File:        %s", MEM_FILE);
        // $display("  Number of Edges:    %0d", NUM_EDGES);
        // $display("  Features per Edge:  %0d", NUM_FEATURES);
        // $display("  Total bits/edge:    %0d bits", NUM_FEATURES * DATA_BITS);
        // $display("  3-Layer Architecture:");
        // $display("    Layer 1: %0d -> %0d", NUM_FEATURES, OUT_FEATURES);
        // $display("    Layer 2: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("    Layer 3: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("========================================");
    // end

endmodule