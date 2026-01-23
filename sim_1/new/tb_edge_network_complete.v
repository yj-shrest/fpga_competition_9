`timescale 1ns / 1ps

module tb_edge_network_complete;

    // Parameters
    parameter CLK_PERIOD = 2;
    parameter NUM_EDGES = 4;
    parameter NUM_NODES = 5;
    parameter NUM_FEATURES = 6;
    parameter OUT_FEATURES = 32;
    parameter DATA_BITS = 8;
    parameter ADDR_BITS = 14;
    parameter NODE_ADDR_BITS = 18;
    parameter MAX_BURST_SIZE = 32;
    parameter BLOCK_NUM = 0;
    
    // Clock and Reset
    reg clk = 0;
    reg rst = 1;
    reg rstn = 0;
    
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // ===============================
    // Edge Encoder Signals
    // ===============================
    reg edge_start = 0;
    wire [OUT_FEATURES*DATA_BITS-1:0] edge_data_out;
    wire [ADDR_BITS-1:0] edge_addr_out;
    wire edge_valid;
    wire edge_done;
    reg [OUT_FEATURES*DATA_BITS-1:0] edge_data_out_reg = 0;
    
    // ===============================
    // Node Encoder Signals
    // ===============================
    reg node_start = 0;
    wire [OUT_FEATURES*DATA_BITS-1:0] node_data_out;
    wire [NODE_ADDR_BITS-1:0] node_addr_out;
    wire node_valid;
    wire node_done;
    reg [OUT_FEATURES*DATA_BITS-1:0] node_data_out_reg = 0;
    
    // ===============================
    // Storage Module Signals
    // ===============================
    // Edge Encoder BRAM interface
    reg encoder_edge_write_start = 0;
    reg [ADDR_BITS-1:0] encoder_edge_write_addr = 0;
    reg encoder_edge_read_start = 0;
    reg [ADDR_BITS-1:0] encoder_edge_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_read_data;
    wire encoder_edge_read_valid;
    wire encoder_edge_write_done;
    wire encoder_edge_write_busy;
    wire encoder_edge_read_busy;
    
    // Buffer0 Edge interface
    reg buf0_edge_write_start = 0;
    reg [ADDR_BITS-1:0] buf0_edge_write_addr = 0;
    reg buf0_edge_read_start = 0;
    reg [ADDR_BITS-1:0] buf0_edge_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_edge_read_data;
    wire buf0_edge_read_valid;
    wire buf0_edge_write_done;
    wire buf0_edge_write_busy;
    wire buf0_edge_read_busy;
    
    // Buffer1 Edge interface (not used in this test)
    reg buf1_edge_write_start = 0;
    reg [ADDR_BITS-1:0] buf1_edge_write_addr = 0;
    
    // Node Encoder BRAM interface
    reg encoder_node_write_start = 0;
    reg [NODE_ADDR_BITS-1:0] encoder_node_write_addr = 0;
    reg encoder_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] encoder_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_read_data;
    wire encoder_node_read_valid;
    wire encoder_node_write_done;
    wire encoder_node_write_busy;
    wire encoder_node_read_busy;
    
    // Buffer0 Node interface
    reg buf0_node_write_start = 0;
    reg [NODE_ADDR_BITS-1:0] buf0_node_write_addr = 0;
    reg buf0_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] buf0_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_node_read_data;
    wire buf0_node_read_valid;
    wire buf0_node_write_done;
    wire buf0_node_write_busy;
    wire buf0_node_read_busy;
    
    // Scatter-Sum interfaces
    reg in_ss_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] in_ss_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_read_data;
    wire in_ss_node_read_valid;
    
    reg out_ss_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] out_ss_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_read_data;
    wire out_ss_node_read_valid;
    
    // Connectivity interfaces
    reg connectivity_src_re = 0;
    reg [ADDR_BITS-1:0] connectivity_src_addr = 0;
    wire [NODE_ADDR_BITS-1:0] connectivity_src_data;
    
    reg connectivity_dst_re = 0;
    reg [ADDR_BITS-1:0] connectivity_dst_addr = 0;
    wire [NODE_ADDR_BITS-1:0] connectivity_dst_data;
    
    // ===============================
    // Edge Network Signals
    // ===============================
    reg en_start = 0;
    wire [DATA_BITS*OUT_FEATURES-1:0] en_edge_output;
    wire en_done;
    
    // Edge Network inputs
    wire [DATA_BITS*OUT_FEATURES-1:0] initial_edge_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] current_edge_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] initial_node_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] current_node_features;
    wire [NODE_ADDR_BITS-1:0] source_node_index;
    wire [NODE_ADDR_BITS-1:0] destination_node_index;
    
    // Edge Network outputs
    wire en_initial_edge_features_re;
    wire en_current_edge_features_re;
    wire en_initial_node_features_re;
    wire en_current_node_features_re;
    wire en_source_node_index_re;
    wire en_destination_node_index_re;
    wire en_current_edge_features_we;
    
    wire en_initial_edge_features_valid;
    wire en_current_edge_features_valid;
    wire en_initial_node_features_valid;
    wire en_current_node_features_valid;
    wire en_source_node_index_valid;
    wire en_destination_node_index_valid;
    wire en_current_edge_features_write_done;
    wire en_in_node_ss_write_done;
    wire en_out_node_ss_write_done;
    
    wire [ADDR_BITS-1:0] en_edge_address;
    wire [NODE_ADDR_BITS-1:0] en_in_node_index_ss;
    wire [NODE_ADDR_BITS-1:0] en_out_node_index_ss;
    wire en_scatter_sum_we;
    wire [NODE_ADDR_BITS-1:0] en_node_index;
    
    // ===============================
    // Data Buffers
    // ===============================
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_encoder_data [0:NUM_EDGES-1];
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_buffer0_data [0:NUM_EDGES-1];
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_edge_network_output [0:NUM_EDGES-1];
    
    // ===============================
    // Test Variables
    // ===============================
    integer edge_counter = 0;
    integer node_counter = 0;
    integer read_counter = 0;
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer edge_network_edge_counter = 0;
    
    // Edge Network monitoring enable
    reg en_monitor_active = 0;
    
    // ===============================
    // DUT Instantiations
    // ===============================
    
    // Register edge data when valid
    always @(posedge clk) begin
        if (rst) begin
            edge_data_out_reg <= 0;
        end else if (edge_valid) begin
            edge_data_out_reg <= edge_data_out;
            $display("[%0t] Captured edge data for address %0d: %h", 
                    $time, edge_addr_out, edge_data_out);
        end
    end
    
    // Register node data when valid
    always @(posedge clk) begin
        if (rst) begin
            node_data_out_reg <= 0;
        end else if (node_valid) begin
            node_data_out_reg <= node_data_out;
            $display("[%0t] Captured node data for address %0d: %h", 
                    $time, node_addr_out, node_data_out);
        end
    end
    
    // ===============================
    // Edge Network Request Monitors
    // ===============================
    
    // Monitor initial edge features requests
    always @(posedge clk) begin
        if (en_monitor_active && en_initial_edge_features_re) begin
            encoder_edge_read_start <= 1;
            encoder_edge_read_addr <= en_edge_address;
            $display("[%0t] Edge Network requested initial edge features at addr %0d", 
                    $time, en_edge_address);
        end else begin
            encoder_edge_read_start <= 0;
        end
    end
    
    // Monitor current edge features requests
    always @(posedge clk) begin
        if (en_monitor_active && en_current_edge_features_re) begin
            buf0_edge_read_start <= 1;
            buf0_edge_read_addr <= en_edge_address;
            $display("[%0t] Edge Network requested current edge features at addr %0d", 
                    $time, en_edge_address);
        end else begin
            buf0_edge_read_start <= 0;
        end
    end
    
    // Monitor initial node features requests
    always @(posedge clk) begin
        if (en_monitor_active && en_initial_node_features_re) begin
            $display("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
            encoder_node_read_start <= 1;
            encoder_node_read_addr <= en_node_index;
            $display("[%0t] Edge Network requested initial node features at addr %0d", 
                    $time, en_node_index);
        end else if (en_monitor_active) begin
            encoder_node_read_start <= 0;
        end
    end
    
    // Monitor current node features requests
    always @(posedge clk) begin
        if (en_monitor_active && en_current_node_features_re) begin
            buf0_node_read_start <= 1;
            buf0_node_read_addr <= en_node_index;
            $display("[%0t] Edge Network requested current node features at addr %0d", 
                    $time, en_node_index);
        end else if (en_monitor_active) begin
            buf0_node_read_start <= 0;
        end
    end
    
    // Monitor source node index requests
    always @(posedge clk) begin
        if (en_monitor_active && en_source_node_index_re) begin
            connectivity_src_re <= 1;
            connectivity_src_addr <= edge_network_edge_counter;
            $display("[%0t] Edge Network requested source node index for edge %0d", 
                    $time, edge_network_edge_counter);
        end else begin
            connectivity_src_re <= 0;
        end
    end
    
    // Monitor destination node index requests
    always @(posedge clk) begin
        if (en_monitor_active && en_destination_node_index_re) begin
            connectivity_dst_re <= 1;
            connectivity_dst_addr <= edge_network_edge_counter;
            $display("[%0t] Edge Network requested destination node index for edge %0d", 
                    $time, edge_network_edge_counter);
        end else begin
            connectivity_dst_re <= 0;
        end
    end
    
    // Monitor Edge Network completion
    always @(posedge clk) begin
        if (en_monitor_active && en_done && edge_network_edge_counter < NUM_EDGES) begin
            expected_edge_network_output[edge_network_edge_counter] = en_edge_output;
            $display("[%0t] Edge Network processed edge %0d: output=%h", 
                    $time, edge_network_edge_counter, en_edge_output);
            edge_network_edge_counter = edge_network_edge_counter + 1;
        end
    end
    
    // Edge Encoder
    edge_encoder #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(NUM_FEATURES),
        .DATA_BITS(DATA_BITS),
        .OUT_FEATURES(OUT_FEATURES),
        .MEM_FILE("edge_initial_features.mem")
    ) encoder (
        .clk(clk),
        .rstn(rstn),
        .start(edge_start),
        .encoded_data(edge_data_out),
        .edge_addr_out(edge_addr_out),
        .data_valid(edge_valid),
        .done(edge_done)
    );
    
    // Node Encoder
    node_encoder #(
        .NUM_NODES(NUM_NODES),
        .NUM_FEATURES(12),  // Adjust based on your node feature file
        .DATA_BITS(DATA_BITS),
        .WEIGHT_BITS(8),
        .BIAS_BITS(8),
        .ADDR_BITS(NODE_ADDR_BITS),
        .OUT_FEATURES(OUT_FEATURES),
        .MEM_FILE("node_initial_features.mem")
    ) node_enc (
        .clk(clk),
        .rstn(rstn),
        .start(node_start),
        .encoded_data(node_data_out),
        .node_addr_out(node_addr_out),
        .data_valid(node_valid),
        .done(node_done)
    );
    
    // Storage Module
    storage_module #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS),
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS),
        .NUM_NODES(NUM_NODES),
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(OUT_FEATURES),
        .MAX_BURST_SIZE(MAX_BURST_SIZE)
    ) storage (
        .clk(clk),
        .rst(rst),
        
        // Edge Encoder BRAM
        .encoder_edge_write_start(encoder_edge_write_start),
        .encoder_edge_write_addr_base(encoder_edge_write_addr),
        .encoder_edge_write_burst_size(6'd32),
        .encoder_edge_write_data(edge_data_out_reg),
        .encoder_edge_write_done(encoder_edge_write_done),
        .encoder_edge_write_busy(encoder_edge_write_busy),
        
        .encoder_edge_read_start(encoder_edge_read_start),
        .encoder_edge_read_addr_base(encoder_edge_read_addr),
        .encoder_edge_read_burst_size(6'd32),
        .encoder_edge_read_data(encoder_edge_read_data),
        .encoder_edge_read_valid(encoder_edge_read_valid),
        .encoder_edge_read_busy(encoder_edge_read_busy),
        
        // Node Encoder BRAM
        .encoder_node_write_start(encoder_node_write_start),
        .encoder_node_write_addr_base(encoder_node_write_addr),
        .encoder_node_write_burst_size(6'd32),
        .encoder_node_write_data(node_data_out_reg),
        .encoder_node_write_done(encoder_node_write_done),
        .encoder_node_write_busy(encoder_node_write_busy),
        
        .encoder_node_read_start(encoder_node_read_start),
        .encoder_node_read_addr_base(encoder_node_read_addr),
        .encoder_node_read_burst_size(6'd32),
        .encoder_node_read_data(encoder_node_read_data),
        .encoder_node_read_valid(encoder_node_read_valid),
        .encoder_node_read_busy(encoder_node_read_busy),
        
        // Connectivity BRAMs
        .connectivity_src_re(connectivity_src_re),
        .connectivity_src_addr(connectivity_src_addr),
        .connectivity_src_data(connectivity_src_data),
        
        .connectivity_dst_re(connectivity_dst_re),
        .connectivity_dst_addr(connectivity_dst_addr),
        .connectivity_dst_data(connectivity_dst_data),
        
        // Buffer0 Edge
        .buf0_edge_write_start(buf0_edge_write_start),
        .buf0_edge_write_addr_base(buf0_edge_write_addr),
        .buf0_edge_write_burst_size(6'd32),
        .buf0_edge_write_data(edge_data_out_reg),
        .buf0_edge_write_done(buf0_edge_write_done),
        .buf0_edge_write_busy(buf0_edge_write_busy),
        
        .buf0_edge_read_start(buf0_edge_read_start),
        .buf0_edge_read_addr_base(buf0_edge_read_addr),
        .buf0_edge_read_burst_size(6'd32),
        .buf0_edge_read_data(buf0_edge_read_data),
        .buf0_edge_read_valid(buf0_edge_read_valid),
        .buf0_edge_read_busy(buf0_edge_read_busy),
        
        // Buffer1 Edge (not used)
        .buf1_edge_write_start(1'b0),
        .buf1_edge_write_addr_base(0),
        .buf1_edge_write_burst_size(0),
        .buf1_edge_write_data(0),
        .buf1_edge_write_done(),
        .buf1_edge_write_busy(),
        
        .buf1_edge_read_start(1'b0),
        .buf1_edge_read_addr_base(0),
        .buf1_edge_read_burst_size(0),
        .buf1_edge_read_data(),
        .buf1_edge_read_valid(),
        .buf1_edge_read_busy(),
        
        // Buffer0 Node
        .buf0_node_write_start(buf0_node_write_start),
        .buf0_node_write_addr_base(buf0_node_write_addr),
        .buf0_node_write_burst_size(6'd32),
        .buf0_node_write_data(node_data_out_reg),
        .buf0_node_write_done(buf0_node_write_done),
        .buf0_node_write_busy(buf0_node_write_busy),
        
        .buf0_node_read_start(buf0_node_read_start),
        .buf0_node_read_addr_base(buf0_node_read_addr),
        .buf0_node_read_burst_size(6'd32),
        .buf0_node_read_data(buf0_node_read_data),
        .buf0_node_read_valid(buf0_node_read_valid),
        .buf0_node_read_busy(buf0_node_read_busy),
        
        // Buffer1 Node (not used)
        .buf1_node_write_start(1'b0),
        .buf1_node_write_addr_base(0),
        .buf1_node_write_burst_size(0),
        .buf1_node_write_data(0),
        .buf1_node_write_done(),
        .buf1_node_write_busy(),
        
        .buf1_node_read_start(1'b0),
        .buf1_node_read_addr_base(0),
        .buf1_node_read_burst_size(0),
        .buf1_node_read_data(),
        .buf1_node_read_valid(),
        .buf1_node_read_busy(),
        
        // Scatter-Sum BRAMs
        .in_ss_node_write_start(1'b0),
        .in_ss_node_write_addr_base(0),
        .in_ss_node_write_burst_size(0),
        .in_ss_node_write_data(0),
        .in_ss_node_write_done(),
        .in_ss_node_write_busy(),
        
        .in_ss_node_read_start(in_ss_node_read_start),
        .in_ss_node_read_addr_base(in_ss_node_read_addr),
        .in_ss_node_read_burst_size(6'd32),
        .in_ss_node_read_data(in_ss_node_read_data),
        .in_ss_node_read_valid(in_ss_node_read_valid),
        .in_ss_node_read_busy(),
        
        .out_ss_node_write_start(1'b0),
        .out_ss_node_write_addr_base(0),
        .out_ss_node_write_burst_size(0),
        .out_ss_node_write_data(0),
        .out_ss_node_write_done(),
        .out_ss_node_write_busy(),
        
        .out_ss_node_read_start(out_ss_node_read_start),
        .out_ss_node_read_addr_base(out_ss_node_read_addr),
        .out_ss_node_read_burst_size(6'd32),
        .out_ss_node_read_data(out_ss_node_read_data),
        .out_ss_node_read_valid(out_ss_node_read_valid),
        .out_ss_node_read_busy()
    );
    
    // Edge Network
    Edge_Network #(
        .BLOCK_NUM(BLOCK_NUM),
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS),
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS),
        .NODE_FEATURES(OUT_FEATURES),
        .EDGE_FEATURES(OUT_FEATURES),
        .MAX_EDGES(NUM_EDGES)
    ) edge_network (
        .clk(clk),
        .rstn(rstn),
        .start(en_start),
        
        // Input features
        .initial_edge_features(initial_edge_features),
        .initial_edge_features_re(en_initial_edge_features_re),
        .initial_edge_features_valid(en_initial_edge_features_valid),
        
        .current_edge_features(current_edge_features),
        .current_edge_features_re(en_current_edge_features_re),
        .current_edge_features_valid(en_current_edge_features_valid),
        .current_edge_features_we(en_current_edge_features_we),
        .current_edge_features_write_done(en_current_edge_features_write_done),
        
        .initial_node_features(initial_node_features),
        .initial_node_features_re(en_initial_node_features_re),
        .initial_node_features_valid(en_initial_node_features_valid),
        
        .current_node_features(current_node_features),
        .current_node_features_re(en_current_node_features_re),
        .current_node_features_valid(en_current_node_features_valid),
        
        .source_node_index(source_node_index),
        .source_node_index_re(en_source_node_index_re),
        .source_node_index_valid(en_source_node_index_valid),
        
        .destination_node_index(destination_node_index),
        .destination_node_index_re(en_destination_node_index_re),
        .destination_node_index_valid(en_destination_node_index_valid),
        
        // Outputs
        .edge_address(en_edge_address),
        .edge_index(),
        .in_node_index_ss(en_in_node_index_ss),
        .in_node_ss_write_done(en_in_node_ss_write_done),
        .out_node_index_ss(en_out_node_index_ss),
        .scatter_sum_we(en_scatter_sum_we),
        .out_node_ss_write_done(en_out_node_ss_write_done),
        .node_index(en_node_index),
        .edge_output(en_edge_output),
        .done(en_done)
    );
    
    // ===============================
    // Data Assignment for Edge Network
    // ===============================
    assign initial_edge_features = encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign current_edge_features = buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign initial_node_features = encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign current_node_features = buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign source_node_index = connectivity_src_data;
    assign destination_node_index = connectivity_dst_data;
    
    assign en_initial_edge_features_valid = encoder_edge_read_valid;
    assign en_current_edge_features_valid = buf0_edge_read_valid;
    assign en_initial_node_features_valid = encoder_node_read_valid;
    assign en_current_node_features_valid = buf0_node_read_valid;
    assign en_source_node_index_valid = 1'b1;
    assign en_destination_node_index_valid = 1'b1;
    
    assign en_current_edge_features_write_done = 1'b1;
    assign en_in_node_ss_write_done = 1'b1;
    assign en_out_node_ss_write_done = 1'b1;
    
    // ===============================
    // Main Test Sequence
    // ===============================
    initial begin
        $display("========================================");
        $display("Starting Complete Edge Network Test");
        $display("========================================");
        
        // Initialize expected data arrays
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            expected_encoder_data[i] = 0;
            expected_buffer0_data[i] = 0;
            expected_edge_network_output[i] = 0;
        end
        
        // Reset
        #100;
        rst = 0;
        rstn = 1;
        #100;
        
        // ===============================
        // PHASE 1: Edge Encoding
        // ===============================
        $display("\n[PHASE 1] Starting edge encoding...");
        edge_start = 1;
        #20;
        edge_start = 0;
        
        fork
            // Monitor encoder output and store to both BRAMs
            begin : phase1_monitor
                while (edge_counter < NUM_EDGES) begin
                    @(posedge clk);
                    if (edge_valid) begin
                        $display("[%0t] Encoding edge %0d: data=%h", 
                                $time, edge_addr_out, edge_data_out);
                        
                        // Store expected data
                        expected_encoder_data[edge_addr_out] = edge_data_out;
                        expected_buffer0_data[edge_addr_out] = edge_data_out;
                        
                        fork
                            begin : write_encoder_bram
                                encoder_edge_write_start <= 1;
                                encoder_edge_write_addr <= edge_addr_out * OUT_FEATURES;
                                @(posedge clk);
                                encoder_edge_write_start <= 0;
                                wait(encoder_edge_write_done);
                            end
                            
                            begin : write_buffer0_bram
                                buf0_edge_write_start <= 1;
                                buf0_edge_write_addr <= edge_addr_out * OUT_FEATURES;
                                @(posedge clk);
                                buf0_edge_write_start <= 0;
                                wait(buf0_edge_write_done);
                            end
                        join
                        edge_counter = edge_counter + 1;
                    end
                end
                $display("[%0t] All edges encoded and stored", $time);
            end
            
            // Wait for encoder to finish
            begin
                wait(edge_done);
                $display("[%0t] Edge encoding complete", $time);
            end
        join
        
        #100;
        
        // ===============================
        // PHASE 2: Verify BRAM Writes
        // ===============================
        $display("\n[PHASE 2] Verifying BRAM writes...");
        
        // Verify Edge Encoder BRAM
        $display("  Verifying Edge Encoder BRAM...");
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            @(posedge clk);
            encoder_edge_write_start = 0;
            encoder_edge_read_start = 1;
            encoder_edge_read_addr = i * OUT_FEATURES;
            @(posedge clk);
            encoder_edge_read_start = 0;
            
            wait(encoder_edge_read_valid);
            @(posedge clk);
            
            if (encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0] === expected_encoder_data[i]) begin
                $display("    Edge %0d: PASS", i);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("    Edge %0d: FAIL", i);
                $display("      Expected: %h", expected_encoder_data[i]);
                $display("      Got: %h", encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]);
                test_fail_count = test_fail_count + 1;
            end
            
            @(posedge clk);
        end
        
        // Verify Buffer0 Edge BRAM
        $display("  Verifying Buffer0 Edge BRAM...");
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            @(posedge clk);
            buf0_edge_write_start = 0;
            buf0_edge_read_start = 1;
            buf0_edge_read_addr = i * OUT_FEATURES;
            @(posedge clk);
            buf0_edge_read_start = 0;
            
            wait(buf0_edge_read_valid);
            @(posedge clk);
            
            if (buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0] === expected_buffer0_data[i]) begin
                $display("    Edge %0d: PASS", i);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("    Edge %0d: FAIL", i);
                $display("      Expected: %h", expected_buffer0_data[i]);
                $display("      Got: %h", buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]);
                test_fail_count = test_fail_count + 1;
            end
            
            @(posedge clk);
        end
        
        #100;
        
        // ===============================
        // PHASE 3: Node Encoding and Storage
        // ===============================
        $display("\n[PHASE 3] Starting node encoding...");
        node_start = 1;
        #20;
        node_start = 0;
        
        fork
            // Monitor node encoder output and store to buffer0_node
            begin : phase3_monitor
                while (node_counter < NUM_NODES) begin
                    @(posedge clk);
                    if (node_valid) begin
                        $display("[%0t] Encoding node %0d: data=%h", 
                                $time, node_addr_out, node_data_out);
                        
                        // Write to both BRAMs in parallel
                        fork
                            begin : write_buffer0_node_bram
                                buf0_node_write_start <= 1;
                                buf0_node_write_addr <= node_addr_out * OUT_FEATURES*DATA_BITS;
                                @(posedge clk);
                                buf0_node_write_start <= 0;
                                wait(buf0_node_write_done);
                            end
                            
                            // Also write to encoder_node BRAM for initial features
                            begin : write_encoder_node_bram
                                encoder_node_write_start <= 1;
                                encoder_node_write_addr <= node_addr_out * OUT_FEATURES*DATA_BITS;
                                @(posedge clk);
                                encoder_node_write_start <= 0;
                                wait(encoder_node_write_done);
                            end
                        join
                        
                        node_counter = node_counter + 1;
                    end
                end
                $display("[%0t] All nodes encoded and stored", $time);
            end
            
            // Wait for node encoder to finish
            begin
                wait(node_done);
                $display("[%0t] Node encoding complete", $time);
            end
        join
        
        #100;
        
        // Verify Node BRAM writes
        $display("  Verifying Buffer0 Node BRAM...");
        for (integer i = 0; i < NUM_NODES; i = i + 1) begin
            @(posedge clk);
            buf0_node_write_start = 0;
            buf0_node_read_start = 1;
            buf0_node_read_addr = i * OUT_FEATURES*DATA_BITS;
            @(posedge clk);
            buf0_node_read_start = 0;
            
            wait(buf0_node_read_valid);
            @(posedge clk);
            
            if (buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0] !== 0) begin
                $display("    Node %0d: PASS (non-zero data: %h)", i, buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0]);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("    Node %0d: FAIL (zero data)", i);
                test_fail_count = test_fail_count + 1;
            end
            
            @(posedge clk);
        end
        
        $display("  Verifying Encoder Node BRAM...");
        for (integer i = 0; i < NUM_NODES; i = i + 1) begin
            @(posedge clk);
            encoder_node_write_start = 0;
            encoder_node_read_start = 1;
            encoder_node_read_addr = i * OUT_FEATURES*DATA_BITS;
            @(posedge clk);
            encoder_node_read_start = 0;
            
            wait(encoder_node_read_valid);
            @(posedge clk);
            
            if (encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0] !== 0) begin
                $display("    Node %0d: PASS (non-zero data: %h)", i, encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0]);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("    Node %0d: FAIL (zero data)", i);
                test_fail_count = test_fail_count + 1;
            end
            
            @(posedge clk);
        end
        
        #100;
        
        // ===============================
        // PHASE 4: Run Edge Network
        // ===============================
        $display("\n[PHASE 4] Running Edge Network...");
        
        // Enable Edge Network monitoring
        en_monitor_active = 1;
        
        // Start Edge Network
        @(posedge clk);
        en_start = 1;
        @(posedge clk);
        en_start = 0;
        
        // Wait for Edge Network to complete all edges
        wait(edge_network_edge_counter >= NUM_EDGES);
        
        #100;
        
        // Disable monitoring
        en_monitor_active = 0;
        
        $display("[%0t] Edge Network completed all edges", $time);
        
        // ===============================
        // PHASE 5: Verify Edge Network Output
        // ===============================
        $display("\n[PHASE 5] Verifying Edge Network output...");
        
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            if (expected_edge_network_output[i] !== 0) begin
                $display("  Edge %0d: Output non-zero (PASS) - %h", 
                        i, expected_edge_network_output[i]);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("  Edge %0d: Output is zero (FAIL)", i);
                test_fail_count = test_fail_count + 1;
            end
        end
        
        // ===============================
        // Test Summary
        // ===============================
        #100;
        $display("\n========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("Total tests passed: %0d", test_pass_count);
        $display("Total tests failed: %0d", test_fail_count);
        $display("Edge encoding complete: %s", edge_done ? "YES" : "NO");
        $display("Node encoding complete: %s", node_done ? "YES" : "NO");
        $display("Edge Network complete: %s", en_done ? "YES" : "NO");
        $display("Edges encoded: %0d", edge_counter);
        $display("Nodes encoded: %0d", node_counter);
        $display("Edges processed by Edge Network: %0d", edge_network_edge_counter);
        $display("========================================");
        
        if (test_fail_count == 0) begin
            $display("SUCCESS: All tests passed!");
        end else begin
            $display("FAILURE: %0d tests failed", test_fail_count);
        end
        $display("========================================");
        
        #100;
        $finish;
    end
    
    // ===============================
    // Waveform Dump
    // ===============================
    initial begin
        $dumpfile("edge_network_complete.vcd");
        $dumpvars(0, tb_edge_network_complete);
    end

endmodule