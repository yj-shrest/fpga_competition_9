`timescale 1ns / 1ps

module tb_node_edge_network_complete;

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
    
    // Buffer1 Edge interface
    reg buf1_edge_write_start = 0;
    reg [ADDR_BITS-1:0] buf1_edge_write_addr = 0;
    reg buf1_edge_read_start = 0;
    reg [ADDR_BITS-1:0] buf1_edge_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_edge_read_data;
    wire buf1_edge_read_valid;
    wire buf1_edge_write_done;
    wire buf1_edge_write_busy;
    wire buf1_edge_read_busy;
    
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
    
    // Buffer1 Node interface
    reg buf1_node_write_start = 0;
    reg [NODE_ADDR_BITS-1:0] buf1_node_write_addr = 0;
    reg buf1_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] buf1_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_node_read_data;
    wire buf1_node_read_valid;
    wire buf1_node_write_done;
    wire buf1_node_write_busy;
    wire buf1_node_read_busy;
    
    // Scatter-Sum interfaces
    reg in_ss_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] in_ss_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_read_data;
    wire in_ss_node_read_valid;
    
    reg out_ss_node_read_start = 0;
    reg [NODE_ADDR_BITS-1:0] out_ss_node_read_addr = 0;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_read_data;
    wire out_ss_node_read_valid;
    
    reg in_ss_node_write_start = 0;
    reg [NODE_ADDR_BITS-1:0] in_ss_node_write_addr = 0;
    reg [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_write_data = 0;
    wire in_ss_node_write_done;
    wire in_ss_node_write_busy;
    
    reg out_ss_node_write_start = 0;
    reg [NODE_ADDR_BITS-1:0] out_ss_node_write_addr = 0;
    reg [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_write_data = 0;
    wire out_ss_node_write_done;
    wire out_ss_node_write_busy;
    
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
    
    wire [DATA_BITS*OUT_FEATURES-1:0] en_initial_edge_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] en_current_edge_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] en_initial_node_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] en_current_node_features;
    wire [NODE_ADDR_BITS-1:0] en_source_node_index;
    wire [NODE_ADDR_BITS-1:0] en_destination_node_index;
    
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
    // Node Network Signals
    // ===============================
    reg nn_start = 0;
    wire [DATA_BITS*OUT_FEATURES-1:0] nn_node_output;
    wire nn_done;
    
    wire [DATA_BITS*OUT_FEATURES-1:0] nn_scatter_sum_features_in;
    wire [DATA_BITS*OUT_FEATURES-1:0] nn_scatter_sum_features_out;
    wire [DATA_BITS*OUT_FEATURES-1:0] nn_current_node_features;
    wire [DATA_BITS*OUT_FEATURES-1:0] nn_initial_node_features;
    
    wire nn_scatter_sum_features_in_re;
    wire nn_scatter_sum_features_out_re;
    wire nn_current_node_features_re;
    wire nn_initial_node_features_re;
    wire nn_current_node_features_we;
    
    wire nn_scatter_sum_features_in_valid;
    wire nn_scatter_sum_features_out_valid;
    wire nn_current_node_features_valid;
    wire nn_initial_node_features_valid;
    wire nn_current_node_features_write_done;
    
    wire [NODE_ADDR_BITS-1:0] nn_node_address;
    wire [NODE_ADDR_BITS-6:0] nn_node_index;
    
    // ===============================
    // Data Buffers
    // ===============================
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_encoder_data [0:NUM_EDGES-1];
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_buffer0_data [0:NUM_EDGES-1];
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_edge_network_output [0:NUM_EDGES-1];
    reg [OUT_FEATURES*DATA_BITS-1:0] expected_node_network_output [0:NUM_NODES-1];
    
    // ===============================
    // Test Variables
    // ===============================
    integer edge_counter = 0;
    integer node_counter = 0;
    integer read_counter = 0;
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer edge_network_edge_counter = 0;
    integer node_network_node_counter = 0;
    
    reg en_monitor_active = 0;
    reg nn_monitor_active = 0;
    reg [ADDR_BITS-1:0] current_edge_idx = 0;
    reg [NODE_ADDR_BITS-1:0] current_node_idx = 0;
    
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
    
    always @(posedge clk) begin
        if (en_monitor_active && en_initial_edge_features_re) begin
            encoder_edge_read_start <= 1;
            encoder_edge_read_addr <= current_edge_idx * OUT_FEATURES;
        end else begin
            encoder_edge_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (en_monitor_active && en_current_edge_features_re) begin
            buf0_edge_read_start <= 1;
            buf0_edge_read_addr <= current_edge_idx * OUT_FEATURES;
        end else begin
            buf0_edge_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (en_monitor_active && en_initial_node_features_re) begin
            encoder_node_read_start <= 1;
            encoder_node_read_addr <= en_node_index;
        end else if (en_monitor_active && !nn_monitor_active) begin
            encoder_node_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (en_monitor_active && en_current_node_features_re) begin
            buf0_node_read_start <= 1;
            buf0_node_read_addr <= en_node_index;
        end else if (en_monitor_active && !nn_monitor_active) begin
            buf0_node_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (en_monitor_active && en_source_node_index_re) begin
            connectivity_src_re <= 1;
            connectivity_src_addr <= current_edge_idx;
        end else begin
            connectivity_src_re <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (en_monitor_active && en_destination_node_index_re) begin
            connectivity_dst_re <= 1;
            connectivity_dst_addr <= current_edge_idx;
        end else begin
            connectivity_dst_re <= 0;
        end
    end
    
    // Monitor and capture scatter-sum writes from Edge Network
    reg en_scatter_sum_we_prev = 0;
    always @(posedge clk) begin
        en_scatter_sum_we_prev <= en_scatter_sum_we;
        
        if (en_monitor_active && en_scatter_sum_we && !en_scatter_sum_we_prev) begin
            // Write to scatter-sum in BRAM
            in_ss_node_write_start <= 1;
            in_ss_node_write_addr <= en_in_node_index_ss;
            in_ss_node_write_data <= {224'b0, en_edge_output};  // Pad to 256 bits
            
            // Write to scatter-sum out BRAM
            out_ss_node_write_start <= 1;
            out_ss_node_write_addr <= en_out_node_index_ss;
            out_ss_node_write_data <= {224'b0, en_edge_output};  // Pad to 256 bits
            
            $display("[%0t] Edge Network wrote scatter-sum: in_idx=%0d, out_idx=%0d, data=%h",
                    $time, en_in_node_index_ss, en_out_node_index_ss, en_edge_output);
        end else begin
            in_ss_node_write_start <= 0;
            out_ss_node_write_start <= 0;
        end
    end
    
    // Monitor Edge Network completion
    reg en_current_edge_features_we_prev = 0;
    always @(posedge clk) begin
        en_current_edge_features_we_prev <= en_current_edge_features_we;
        
        if (en_monitor_active && en_current_edge_features_we && !en_current_edge_features_we_prev && edge_network_edge_counter < NUM_EDGES) begin
            // Write updated edge features to buffer1
            buf1_edge_write_start <= 1;
            buf1_edge_write_addr <= current_edge_idx * OUT_FEATURES;
            
            expected_edge_network_output[edge_network_edge_counter] = en_edge_output;
            $display("[%0t] Edge Network processed edge %0d: output=%h", 
                    $time, edge_network_edge_counter, en_edge_output);
            edge_network_edge_counter = edge_network_edge_counter + 1;
            current_edge_idx <= current_edge_idx + 1;
        end else begin
            buf1_edge_write_start <= 0;
        end
    end
    
    // ===============================
    // Node Network Request Monitors
    // ===============================
    
    always @(posedge clk) begin
        if (nn_monitor_active && nn_scatter_sum_features_in_re) begin
            in_ss_node_read_start <= 1;
            in_ss_node_read_addr <= nn_node_address;
            $display("[%0t] TB: Reading scatter_sum_in for addr=%0d", $time, nn_node_address);
        end else if (nn_monitor_active) begin
            in_ss_node_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (nn_monitor_active && nn_scatter_sum_features_out_re) begin
            out_ss_node_read_start <= 1;
            out_ss_node_read_addr <= nn_node_address;
        end else if (nn_monitor_active) begin
            out_ss_node_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (nn_monitor_active && nn_current_node_features_re) begin
            buf0_node_read_start <= 1;
            buf0_node_read_addr <= nn_node_address;
        end else if (nn_monitor_active && !en_monitor_active) begin
            buf0_node_read_start <= 0;
        end
    end
    
    always @(posedge clk) begin
        if (nn_monitor_active && nn_initial_node_features_re) begin
            encoder_node_read_start <= 1;
            encoder_node_read_addr <= nn_node_address;
        end else if (nn_monitor_active && !en_monitor_active) begin
            encoder_node_read_start <= 0;
        end
    end
    
    // Monitor Node Network completion
    reg nn_current_node_features_we_prev = 0;
    always @(posedge clk) begin
        nn_current_node_features_we_prev <= nn_current_node_features_we;
        
        if (nn_monitor_active && nn_current_node_features_we && !nn_current_node_features_we_prev && node_network_node_counter < NUM_NODES) begin
            // Write updated node features to buffer1
            buf1_node_write_start <= 1;
            buf1_node_write_addr <= nn_node_address;
            
            expected_node_network_output[node_network_node_counter] = nn_node_output;
            $display("[%0t] Node Network processed node %0d: output=%h", 
                    $time, node_network_node_counter, nn_node_output);
            node_network_node_counter = node_network_node_counter + 1;
            current_node_idx <= current_node_idx + 1;
        end else begin
            buf1_node_write_start <= 0;
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
        .NUM_FEATURES(12),
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
        
        // Buffer1 Edge
        .buf1_edge_write_start(buf1_edge_write_start),
        .buf1_edge_write_addr_base(buf1_edge_write_addr),
        .buf1_edge_write_burst_size(6'd32),
        .buf1_edge_write_data({224'b0, en_edge_output}),
        .buf1_edge_write_done(buf1_edge_write_done),
        .buf1_edge_write_busy(buf1_edge_write_busy),
        
        .buf1_edge_read_start(buf1_edge_read_start),
        .buf1_edge_read_addr_base(buf1_edge_read_addr),
        .buf1_edge_read_burst_size(6'd32),
        .buf1_edge_read_data(buf1_edge_read_data),
        .buf1_edge_read_valid(buf1_edge_read_valid),
        .buf1_edge_read_busy(buf1_edge_read_busy),
        
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
        
        // Buffer1 Node
        .buf1_node_write_start(buf1_node_write_start),
        .buf1_node_write_addr_base(buf1_node_write_addr),
        .buf1_node_write_burst_size(6'd32),
        .buf1_node_write_data({224'b0, nn_node_output}),
        .buf1_node_write_done(buf1_node_write_done),
        .buf1_node_write_busy(buf1_node_write_busy),
        
        .buf1_node_read_start(buf1_node_read_start),
        .buf1_node_read_addr_base(buf1_node_read_addr),
        .buf1_node_read_burst_size(6'd32),
        .buf1_node_read_data(buf1_node_read_data),
        .buf1_node_read_valid(buf1_node_read_valid),
        .buf1_node_read_busy(buf1_node_read_busy),
        
        // Scatter-Sum BRAMs
        .in_ss_node_write_start(in_ss_node_write_start),
        .in_ss_node_write_addr_base(in_ss_node_write_addr),
        .in_ss_node_write_burst_size(6'd32),
        .in_ss_node_write_data(in_ss_node_write_data),
        .in_ss_node_write_done(in_ss_node_write_done),
        .in_ss_node_write_busy(in_ss_node_write_busy),
        
        .in_ss_node_read_start(in_ss_node_read_start),
        .in_ss_node_read_addr_base(in_ss_node_read_addr),
        .in_ss_node_read_burst_size(6'd32),
        .in_ss_node_read_data(in_ss_node_read_data),
        .in_ss_node_read_valid(in_ss_node_read_valid),
        .in_ss_node_read_busy(),
        
        .out_ss_node_write_start(out_ss_node_write_start),
        .out_ss_node_write_addr_base(out_ss_node_write_addr),
        .out_ss_node_write_burst_size(6'd32),
        .out_ss_node_write_data(out_ss_node_write_data),
        .out_ss_node_write_done(out_ss_node_write_done),
        .out_ss_node_write_busy(out_ss_node_write_busy),
        
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
        
        .initial_edge_features(en_initial_edge_features),
        .initial_edge_features_re(en_initial_edge_features_re),
        .initial_edge_features_valid(en_initial_edge_features_valid),
        
        .current_edge_features(en_current_edge_features),
        .current_edge_features_re(en_current_edge_features_re),
        .current_edge_features_valid(en_current_edge_features_valid),
        .current_edge_features_we(en_current_edge_features_we),
        .current_edge_features_write_done(en_current_edge_features_write_done),
        
        .initial_node_features(en_initial_node_features),
        .initial_node_features_re(en_initial_node_features_re),
        .initial_node_features_valid(en_initial_node_features_valid),
        
        .current_node_features(en_current_node_features),
        .current_node_features_re(en_current_node_features_re),
        .current_node_features_valid(en_current_node_features_valid),
        
        .source_node_index(en_source_node_index),
        .source_node_index_re(en_source_node_index_re),
        .source_node_index_valid(en_source_node_index_valid),
        
        .destination_node_index(en_destination_node_index),
        .destination_node_index_re(en_destination_node_index_re),
        .destination_node_index_valid(en_destination_node_index_valid),
        
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
    
    // Node Network
    Node_Network #(
        .BLOCK_NUM(BLOCK_NUM),
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS),
        .NODE_FEATURES(OUT_FEATURES),
        .MAX_NODES(NUM_NODES)
    ) node_network (
        .clk(clk),
        .rstn(rstn),
        .start(nn_start),
        
        .scatter_sum_features_in(nn_scatter_sum_features_in),
        .scatter_sum_features_in_re(nn_scatter_sum_features_in_re),
        .scatter_sum_features_in_valid(nn_scatter_sum_features_in_valid),
        
        .scatter_sum_features_out(nn_scatter_sum_features_out),
        .scatter_sum_features_out_re(nn_scatter_sum_features_out_re),
        .scatter_sum_features_out_valid(nn_scatter_sum_features_out_valid),
        
        .current_node_features(nn_current_node_features),
        .current_node_features_re(nn_current_node_features_re),
        .current_node_features_valid(nn_current_node_features_valid),
        .current_node_features_we(nn_current_node_features_we),
        .current_node_features_write_done(nn_current_node_features_write_done),
        
        .initial_node_features(nn_initial_node_features),
        .initial_node_features_re(nn_initial_node_features_re),
        .initial_node_features_valid(nn_initial_node_features_valid),
        
        .node_address(nn_node_address),
        .node_index(nn_node_index),
        .node_output(nn_node_output),
        .done(nn_done)
    );
    
    // ===============================
    // Data Assignments for Edge Network
    // ===============================
    assign en_initial_edge_features = encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign en_current_edge_features = buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign en_initial_node_features = encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign en_current_node_features = buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign en_source_node_index = connectivity_src_data;
    assign en_destination_node_index = connectivity_dst_data;
    
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
    // Data Assignments for Node Network
    // ===============================
    assign nn_scatter_sum_features_in = in_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign nn_scatter_sum_features_out = out_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign nn_current_node_features = buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    assign nn_initial_node_features = encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0];
    
    assign nn_scatter_sum_features_in_valid = in_ss_node_read_valid;
    assign nn_scatter_sum_features_out_valid = out_ss_node_read_valid;
    assign nn_current_node_features_valid = buf0_node_read_valid;
    assign nn_initial_node_features_valid = encoder_node_read_valid;
    
    assign nn_current_node_features_write_done = 1'b1;
    
    // ===============================
    // Test Sequence
    // ===============================
    initial begin
        // Initialize
        rst = 1;
        rstn = 0;
        #(CLK_PERIOD*10);
        rst = 0;
        rstn = 1;
        #(CLK_PERIOD*10);
        
        $display("\n========================================");
        $display("STARTING COMPLETE GNN TEST");
        $display("========================================\n");
        
        // ===============================
        // PHASE 1: Edge Encoding and Storage
        // ===============================
        $display("[PHASE 1] Starting edge encoding...");
        edge_start = 1;
        #20;
        edge_start = 0;
        
        fork
            begin : phase1_monitor
                while (edge_counter < NUM_EDGES) begin
                    @(posedge clk);
                    if (edge_valid) begin
                        $display("[%0t] Encoding edge %0d: addr=%0d, data=%h", 
                                $time, edge_addr_out, edge_addr_out, edge_data_out);
                        
                        fork
                            begin : write_encoder_edge_bram
                                encoder_edge_write_start <= 1;
                                encoder_edge_write_addr <= edge_addr_out * OUT_FEATURES;
                                @(posedge clk);
                                encoder_edge_write_start <= 0;
                                wait(encoder_edge_write_done);
                            end
                            
                            begin : write_buffer0_edge_bram
                                buf0_edge_write_start <= 1;
                                buf0_edge_write_addr <= edge_addr_out * OUT_FEATURES;
                                @(posedge clk);
                                buf0_edge_write_start <= 0;
                                wait(buf0_edge_write_done);
                            end
                        join
                        
                        expected_encoder_data[edge_counter] = edge_data_out;
                        expected_buffer0_data[edge_counter] = edge_data_out;
                        edge_counter = edge_counter + 1;
                    end
                end
                $display("[%0t] All edges encoded and stored", $time);
            end
            
            begin
                wait(edge_done);
                $display("[%0t] Edge encoding complete", $time);
            end
        join
        
        #100;
        
        // ===============================
        // PHASE 2: Node Encoding and Storage
        // ===============================
        $display("\n[PHASE 2] Starting node encoding...");
        node_start = 1;
        #20;
        node_start = 0;
        
        fork
            begin : phase2_monitor
                while (node_counter < NUM_NODES) begin
                    @(posedge clk);
                    if (node_valid) begin
                        $display("[%0t] Encoding node %0d: data=%h", 
                                $time, node_addr_out, node_data_out);
                        
                        fork
                            begin : write_buffer0_node_bram
                                buf0_node_write_start <= 1;
                                buf0_node_write_addr <= node_addr_out * OUT_FEATURES*DATA_BITS;
                                @(posedge clk);
                                buf0_node_write_start <= 0;
                                wait(buf0_node_write_done);
                            end
                            
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
            
            begin
                wait(node_done);
                $display("[%0t] Node encoding complete", $time);
            end
        join
        
        #100;
        
        // ===============================
        // PHASE 3: Run Edge Network
        // ===============================
        $display("\n[PHASE 3] Running Edge Network...");
        
        en_monitor_active = 1;
        current_edge_idx = 0;
        
        @(posedge clk);
        en_start = 1;
        @(posedge clk);
        en_start = 0;
        
        wait(edge_network_edge_counter >= NUM_EDGES);
        
        #100;
        
        en_monitor_active = 0;
        
        $display("[%0t] Edge Network completed all edges", $time);
        
        #100;
        
        // ===============================
        // PHASE 4: Run Node Network
        // ===============================
        $display("\n[PHASE 4] Running Node Network...");
        
        nn_monitor_active = 1;
        current_node_idx = 0;
        
        @(posedge clk);
        nn_start = 1;
        @(posedge clk);
        nn_start = 0;
        
        wait(node_network_node_counter >= NUM_NODES);
        
        #100;
        
        nn_monitor_active = 0;
        
        $display("[%0t] Node Network completed all nodes", $time);
        
        #100;
        
        // ===============================
        // PHASE 5: Verify Results
        // ===============================
        $display("\n[PHASE 5] Verifying results...");
        
        $display("  Verifying Edge Network output...");
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
        
        $display("  Verifying Node Network output...");
        for (integer i = 0; i < NUM_NODES; i = i + 1) begin
            if (expected_node_network_output[i] !== 0) begin
                $display("  Node %0d: Output non-zero (PASS) - %h", 
                        i, expected_node_network_output[i]);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("  Node %0d: Output is zero (FAIL)", i);
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
        $display("Node Network complete: %s", nn_done ? "YES" : "NO");
        $display("Edges encoded: %0d", edge_counter);
        $display("Nodes encoded: %0d", node_counter);
        $display("Edges processed by Edge Network: %0d", edge_network_edge_counter);
        $display("Nodes processed by Node Network: %0d", node_network_node_counter);
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
        $dumpfile("node_edge_network_complete.vcd");
        $dumpvars(0, tb_node_edge_network_complete);
    end

endmodule