`timescale 1ns / 1ps

module edge_decoder
#(
    parameter NUM_EDGES      = 4,
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8,
    parameter ADDR_BITS      = 14,
    parameter OUT_FEATURES   = 32,
    parameter MEM_FILE       = "",
    parameter OUTPUT_FILE    = "edge_decoder_output.txt"
)
(
    input  clk,
    input  rstn,
    input  start,
    
    // Optional: Output the encoded results
    output reg [DATA_BITS-1:0] decoded_data,
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
                     LAYER3      = 3'b100,  // Added Layer3 state
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
    // File handle for writing output
    //============================================
    integer output_file_handle = 0;
    integer edge_counter;
    integer byte_counter;
    integer file_handle;
    integer read_success;
    integer i;
    
    //============================================
    // Layer Interconnections
    //============================================
    reg layer1_rstn;
    wire [NUM_FEATURES*DATA_BITS-1:0] layer1_in;
    wire [OUT_FEATURES*DATA_BITS-1:0] layer1_out;
    wire layer1_done;
    
    reg layer2_rstn;
    wire [DATA_BITS-1:0] layer2_out;
    wire layer2_done;

    reg layer3_rstn;
    wire [DATA_BITS-1:0] layer3_out;
    wire layer3_done;
    
    // Data registers
    reg [OUT_FEATURES*DATA_BITS-1:0] layer1_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] layer2_out_reg;
    reg [DATA_BITS-1:0] decoded_features_reg;
    
    //============================================
    // Instantiate Layer 1
    //============================================
    Edge_Decoder_Layer #(
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
    edge_output_layer #(
        .LAYER_NO      (1),
        .NUM_NEURONS   (32),
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

    edge_output_transform #(
        .LAYER_NO      (2),
        .NUM_NEURONS   (1),
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
    integer j, k;
    //============================================
    // Initialize Memory from File
    //============================================
    initial begin
        
        
        $display("========================================");
        $display("Loading edge features from: %s", MEM_FILE);
        $display("========================================");
        
        // Use $readmemb with a temporary array
        if (MEM_FILE != "") begin
            
            $readmemb(MEM_FILE, temp_array);
            
            // Load NUM_FEATURES bytes for each edge
            for (j = 0; j < NUM_EDGES; j = j + 1) begin
                for (k = 0; k < NUM_FEATURES; k = k + 1) begin
                    edge_mem[j][k*DATA_BITS +: DATA_BITS] = temp_array[(j*NUM_FEATURES) + k];
                end
                $display("Edge %0d: %h", j, edge_mem[j]);
            end
            
            $display("Total edges loaded: %0d", NUM_EDGES);
        end else begin
            $display("MEM_FILE is empty - edge_mem will be zero-initialized");
            $display("Note: Data should be provided via external interface");
        end
        $display("========================================");
    end
    
    //============================================
    // State Register
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
        end else begin
            if (state != next_state) begin
                case (next_state)
                    IDLE:       $display("[DECODER][%0t] FSM: IDLE (edge_idx=%0d)", $time, edge_idx);
                    READ_EDGE:  $display("[DECODER][%0t] FSM: READ_EDGE (edge_idx=%0d)", $time, edge_idx);
                    LAYER1:     $display("[DECODER][%0t] FSM: LAYER1 (edge_idx=%0d)", $time, edge_idx);
                    LAYER2:     $display("[DECODER][%0t] FSM: LAYER2 (edge_idx=%0d, layer1_done=%b)", $time, edge_idx, layer1_done);
                    WRITE:      $display("[DECODER][%0t] FSM: WRITE (edge_idx=%0d, layer2_done=%b)", $time, edge_idx, layer2_done);
                    NEXT_EDGE:  $display("[DECODER][%0t] FSM: NEXT_EDGE (edge_idx=%0d)", $time, edge_idx);
                    FINISH:     $display("[DECODER][%0t] FSM: FINISH (edge_idx=%0d)", $time, edge_idx);
                endcase
            end
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
        decoded_data = 0;
        edge_addr_out = 0;
        data_valid = 0;
        
        case (state)
            WRITE: begin
                decoded_data = decoded_features_reg;
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
    // Layer Reset Control - FIXED v2 with DEBUG
    //============================================
    always @(*) begin
        // Default: keep layers active
        layer1_rstn = rstn;
        layer2_rstn = rstn;
        
        case (state)
            IDLE: begin
                // Both in reset when idle
                layer1_rstn = 0;
                layer2_rstn = 0;
            end
            
            READ_EDGE: begin
                // Reset layer1 so it's ready to start in LAYER1 state
                layer1_rstn = 0;
                // Keep layer2 active (it will be reset when we reach LAYER1)
                layer2_rstn = rstn;
            end
            
            // Note: In LAYER1 and LAYER2 states, keep both active
            // The layers self-manage via their counter logic
            
            default: begin
                // All other states: both layers active
                layer1_rstn = rstn;
                layer2_rstn = rstn;
            end
        endcase
    end
    
    // Debug reset signals
    always @(posedge clk) begin
        if (state == LAYER2 && !layer2_rstn) begin
            $display("[DECODER][%0t] ERROR: layer2_rstn=0 in LAYER2 state! rstn=%b, state=%b", 
                    $time, rstn, state);
        end
    end
    
    //============================================
    // Data Path Registers
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_edge_data <= 0;
            layer1_out_reg <= 0;
            layer2_out_reg <= 0;
            decoded_features_reg <= 0;
        end else begin
            case (state)
                READ_EDGE: begin
                    // Read edge data from internal memory
                    current_edge_data <= edge_mem[edge_idx];
                    $display("[DECODER][%0t] === Processing Edge %0d: Input = %h ===", 
                            $time, edge_idx, edge_mem[edge_idx]);
                end
                
                LAYER1: begin
                    if (layer1_done) begin
                        layer1_out_reg <= layer1_out;
                        $display("[DECODER][%0t]   Edge %0d Layer1 Output: %h", $time, edge_idx, layer1_out);
                    end
                end

                LAYER2: begin
                    if (layer2_done) begin
                        layer2_out_reg <= layer2_out;
                        $display("[DECODER][%0t]   Edge %0d Layer2 Output: %h", $time, edge_idx, layer2_out);
                    end
                end
                
                LAYER3: begin
                    $display("[DECODER][%0t]   Edge %0d Layer3: layer3_rstn=%b, layer3_done=%b, layer3_out=%h", 
                            $time, edge_idx, layer3_rstn, layer3_done, layer3_out);
                    if (layer3_done) begin
                        decoded_features_reg <= layer3_out;
                        $display("[DECODER][%0t]   Edge %0d Layer3 Output (Final): %h", $time, edge_idx, layer3_out);
                    end
                end
                
                WRITE: begin
                    $display("[DECODER][%0t]   Edge %0d WRITE: decoded_data=%h, valid=%b", 
                            $time, edge_idx, decoded_features_reg, 1'b1);
                    
                    // Write to output file in binary format
                    if (output_file_handle != 0 && OUTPUT_FILE != "") begin
                        $fwrite(output_file_handle, "%b\n", decoded_features_reg);
                    end
                end
                
                FINISH: begin
                    $display("[DECODER][%0t] ========================================", $time);
                    $display("[DECODER][%0t] ALL %0d EDGES PROCESSED COMPLETELY", $time, NUM_EDGES);
                    $display("[DECODER][%0t] ========================================", $time);
                    
                    // Close output file
                    if (output_file_handle != 0 && OUTPUT_FILE != "") begin
                        $fclose(output_file_handle);
                        $display("[DECODER] Output file closed: %s", OUTPUT_FILE);
                    end
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
    
    //============================================
    // Open output file for writing
    //============================================
    initial begin
        if (OUTPUT_FILE != "") begin
            output_file_handle = $fopen(OUTPUT_FILE, "w");
            if (output_file_handle == 0) begin
                $display("[DECODER] ERROR: Could not open output file: %s", OUTPUT_FILE);
            end else begin
                $display("[DECODER] Output file opened: %s", OUTPUT_FILE);
            end
        end
    end
    
endmodule