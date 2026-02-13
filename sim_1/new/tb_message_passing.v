`timescale 1ns / 1ps

module tb_message_passing_simplified;

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
    parameter BLOCK_NUM = 0;  // Change to test different blocks
    
    // Determine if BLOCK_NUM is even or odd
    localparam IS_EVEN = (BLOCK_NUM % 2 == 0);
    
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
    
    // ===============================
    // Node Encoder Signals
    // ===============================
    reg node_start = 0;
    wire [OUT_FEATURES*DATA_BITS-1:0] node_data_out;
    wire [NODE_ADDR_BITS-1:0] node_addr_out;
    wire node_valid;
    wire node_done;
    
    // ===============================
    // Storage Module Signals
    // ===============================
    // Edge Encoder BRAM
    wire encoder_edge_write_start;
    wire [ADDR_BITS-1:0] encoder_edge_write_addr;
    wire encoder_edge_read_start;
    wire [ADDR_BITS-1:0] encoder_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_read_data;
    wire encoder_edge_read_valid;
    wire encoder_edge_write_done;
    
    // Buffer0 Edge
    wire buf0_edge_write_start;
    wire [ADDR_BITS-1:0] buf0_edge_write_addr;
    wire buf0_edge_read_start;
    wire [ADDR_BITS-1:0] buf0_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_edge_read_data;
    wire buf0_edge_read_valid;
    wire buf0_edge_write_done;
    
    // Buffer1 Edge
    wire buf1_edge_write_start;
    wire [ADDR_BITS-1:0] buf1_edge_write_addr;
    wire buf1_edge_read_start;
    wire [ADDR_BITS-1:0] buf1_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_edge_read_data;
    wire buf1_edge_read_valid;
    wire buf1_edge_write_done;
    
    // Node Encoder BRAM
    wire encoder_node_write_start;
    wire [NODE_ADDR_BITS-1:0] encoder_node_write_addr;
    wire encoder_node_read_start;
    wire [NODE_ADDR_BITS-1:0] encoder_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_read_data;
    wire encoder_node_read_valid;
    wire encoder_node_write_done;
    
    // Buffer0 Node
    wire buf0_node_write_start;
    wire [NODE_ADDR_BITS-1:0] buf0_node_write_addr;
    wire buf0_node_read_start;
    wire [NODE_ADDR_BITS-1:0] buf0_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_node_read_data;
    wire buf0_node_read_valid;
    wire buf0_node_write_done;
    
    // Buffer1 Node
    wire buf1_node_write_start;
    wire [NODE_ADDR_BITS-1:0] buf1_node_write_addr;
    wire buf1_node_read_start;
    wire [NODE_ADDR_BITS-1:0] buf1_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_node_read_data;
    wire buf1_node_read_valid;
    wire buf1_node_write_done;
    
    // Scatter-Sum In
    wire in_ss_node_read_start;
    wire [NODE_ADDR_BITS-1:0] in_ss_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_read_data;
    wire in_ss_node_read_valid;
    wire in_ss_node_write_start;
    wire [NODE_ADDR_BITS-1:0] in_ss_node_write_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_write_data;
    wire in_ss_node_write_done;
    
    // Scatter-Sum Out
    wire out_ss_node_read_start;
    wire [NODE_ADDR_BITS-1:0] out_ss_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_read_data;
    wire out_ss_node_read_valid;
    wire out_ss_node_write_start;
    wire [NODE_ADDR_BITS-1:0] out_ss_node_write_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_write_data;
    wire out_ss_node_write_done;
    
    // Connectivity
    wire connectivity_src_re;
    wire [ADDR_BITS-1:0] connectivity_src_addr;
    wire [NODE_ADDR_BITS-1:0] connectivity_src_data;
    wire connectivity_dst_re;
    wire [ADDR_BITS-1:0] connectivity_dst_addr;
    wire [NODE_ADDR_BITS-1:0] connectivity_dst_data;
    
    // ===============================
    // Message Passing Signals
    // ===============================
    reg mp_start = 0;
    wire mp_done;
    
    // Message Passing to Storage connections
    wire mp_initial_edge_features_re;
    wire mp_edge_buf0_re;
    wire mp_edge_buf0_we;
    wire mp_edge_buf1_re;
    wire mp_edge_buf1_we;
    wire mp_initial_node_features_edge_re;
    wire mp_node_buf0_re_edge;
    wire mp_node_buf1_re_edge;
    wire mp_source_node_index_re;
    wire mp_destination_node_index_re;
    wire [ADDR_BITS-1:0] mp_edge_address;
    wire [ADDR_BITS-6:0] mp_edge_index;
    wire [NODE_ADDR_BITS-1:0] mp_in_node_index_ss;
    wire [NODE_ADDR_BITS-1:0] mp_out_node_index_ss;
    wire mp_scatter_sum_we;
    wire [NODE_ADDR_BITS-1:0] mp_edge_net_node_index;
    wire [DATA_BITS*OUT_FEATURES-1:0] mp_edge_output;
    wire mp_scatter_sum_features_in_re;
    wire mp_scatter_sum_features_out_re;
    wire mp_initial_node_features_node_re;
    wire mp_node_buf0_re_node;
    wire mp_node_buf0_we;
    wire mp_node_buf1_re_node;
    wire mp_node_buf1_we;
    wire [NODE_ADDR_BITS-1:0] mp_node_address;
    wire [NODE_ADDR_BITS-6:0] mp_node_index;
    wire [DATA_BITS*OUT_FEATURES-1:0] mp_node_output;
    
    // ===============================
    // Encoder to Storage Connections
    // ===============================
    // These connect encoder outputs to storage writes
    assign encoder_edge_write_start = edge_valid;
    assign encoder_edge_write_addr = edge_addr_out * OUT_FEATURES;
    
    assign buf0_edge_write_start = mp_edge_buf0_we ||edge_valid;  // Initial edge data always to buf0
    assign buf0_edge_write_addr = mp_edge_buf0_we ? mp_edge_address : edge_addr_out * OUT_FEATURES;
    
    assign encoder_node_write_start = node_valid;
    assign encoder_node_write_addr = node_addr_out * OUT_FEATURES;
    
    //todo: OR with node encoder and node network writes
    assign buf0_node_write_start = mp_node_buf0_we || node_valid;  // Initial node data always to buf0
    assign buf0_node_write_addr = mp_node_buf0_we ? mp_node_address : node_addr_out * OUT_FEATURES;
    
    // ===============================
    // Message Passing to Storage Connections
    // ===============================
    // Connect MP read requests directly to storage
    assign encoder_edge_read_start = mp_initial_edge_features_re;
    assign encoder_edge_read_addr = mp_edge_address;
    
    assign buf0_edge_read_start = mp_edge_buf0_re;
    assign buf0_edge_read_addr = mp_edge_address;
    
    assign buf1_edge_read_start = mp_edge_buf1_re;
    assign buf1_edge_read_addr = mp_edge_address;
    
    assign encoder_node_read_start = mp_initial_node_features_edge_re | mp_initial_node_features_node_re;
    assign encoder_node_read_addr = mp_initial_node_features_edge_re ? mp_edge_net_node_index : mp_node_address;
    
    assign buf0_node_read_start = mp_node_buf0_re_edge | mp_node_buf0_re_node;
    assign buf0_node_read_addr = mp_node_buf0_re_edge ? mp_edge_net_node_index : mp_node_address;
    
    assign buf1_node_read_start = mp_node_buf1_re_edge | mp_node_buf1_re_node;
    assign buf1_node_read_addr = mp_node_buf1_re_edge ? mp_edge_net_node_index : mp_node_address;
    
    assign connectivity_src_re = mp_source_node_index_re;
    assign connectivity_src_addr = mp_edge_index;
    
    assign connectivity_dst_re = mp_destination_node_index_re;
    assign connectivity_dst_addr = mp_edge_index;
    
    // Scatter-sum writes from Edge Network
    assign in_ss_node_write_start = mp_scatter_sum_we;
    assign in_ss_node_write_addr = mp_in_node_index_ss;
    assign in_ss_node_write_data = {224'b0, mp_edge_output};
    
    assign out_ss_node_write_start = mp_scatter_sum_we;
    assign out_ss_node_write_addr = mp_out_node_index_ss;
    assign out_ss_node_write_data = {224'b0, mp_edge_output};
    
    // Scatter-sum reads for Node Network
    assign in_ss_node_read_start = mp_scatter_sum_features_in_re;
    assign in_ss_node_read_addr = mp_node_address;
    
    assign out_ss_node_read_start = mp_scatter_sum_features_out_re;
    assign out_ss_node_read_addr = mp_node_address;
    
    // Edge Network writes to buffers
    assign buf1_edge_write_start = mp_edge_buf1_we;
    assign buf1_edge_write_addr = mp_edge_address;
    
    // Note: buf0_edge_write is OR'd with encoder writes (already assigned above)
    // For proper operation, storage module should handle multiple write sources
    
    // Node Network writes to buffers
    assign buf1_node_write_start = mp_node_buf1_we;
    assign buf1_node_write_addr = mp_node_address;
    
    // Note: buf0_node_write is OR'd with encoder writes (already assigned above)
    
    // ===============================
    // Test Variables
    // ===============================
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    
    // ===============================
    // DUT Instantiations
    // ===============================
    
    // Edge Encoder
    edge_encoder #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(NUM_FEATURES),
        .DATA_BITS(DATA_BITS),
        .OUT_FEATURES(OUT_FEATURES),
        .MEM_FILE("edge_initial_features.mem")
    ) edge_enc (
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
        .encoder_edge_write_data(edge_data_out),
        .encoder_edge_write_done(encoder_edge_write_done),
        .encoder_edge_write_busy(),
        
        .encoder_edge_read_start(encoder_edge_read_start),
        .encoder_edge_read_addr_base(encoder_edge_read_addr),
        .encoder_edge_read_burst_size(6'd32),
        .encoder_edge_read_data(encoder_edge_read_data),
        .encoder_edge_read_valid(encoder_edge_read_valid),
        .encoder_edge_read_busy(),
        
        // Node Encoder BRAM
        .encoder_node_write_start(encoder_node_write_start),
        .encoder_node_write_addr_base(encoder_node_write_addr),
        .encoder_node_write_burst_size(6'd32),
        .encoder_node_write_data(node_data_out),
        .encoder_node_write_done(encoder_node_write_done),
        .encoder_node_write_busy(),
        
        .encoder_node_read_start(encoder_node_read_start),
        .encoder_node_read_addr_base(encoder_node_read_addr),
        .encoder_node_read_burst_size(6'd32),
        .encoder_node_read_data(encoder_node_read_data),
        .encoder_node_read_valid(encoder_node_read_valid),
        .encoder_node_read_busy(),
        
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
        .buf0_edge_write_data(edge_data_out),
        .buf0_edge_write_done(buf0_edge_write_done),
        .buf0_edge_write_busy(),
        
        .buf0_edge_read_start(buf0_edge_read_start),
        .buf0_edge_read_addr_base(buf0_edge_read_addr),
        .buf0_edge_read_burst_size(6'd32),
        .buf0_edge_read_data(buf0_edge_read_data),
        .buf0_edge_read_valid(buf0_edge_read_valid),
        .buf0_edge_read_busy(),
        
        // Buffer1 Edge
        .buf1_edge_write_start(buf1_edge_write_start),
        .buf1_edge_write_addr_base(buf1_edge_write_addr),
        .buf1_edge_write_burst_size(6'd32),
        .buf1_edge_write_data(mp_edge_output),
        .buf1_edge_write_done(buf1_edge_write_done),
        .buf1_edge_write_busy(),
        
        .buf1_edge_read_start(buf1_edge_read_start),
        .buf1_edge_read_addr_base(buf1_edge_read_addr),
        .buf1_edge_read_burst_size(6'd32),
        .buf1_edge_read_data(buf1_edge_read_data),
        .buf1_edge_read_valid(buf1_edge_read_valid),
        .buf1_edge_read_busy(),
        
        // Buffer0 Node
        .buf0_node_write_start(buf0_node_write_start),
        .buf0_node_write_addr_base(buf0_node_write_addr),
        .buf0_node_write_burst_size(6'd32),
        .buf0_node_write_data(node_data_out),
        .buf0_node_write_done(buf0_node_write_done),
        .buf0_node_write_busy(),
        
        .buf0_node_read_start(buf0_node_read_start),
        .buf0_node_read_addr_base(buf0_node_read_addr),
        .buf0_node_read_burst_size(6'd32),
        .buf0_node_read_data(buf0_node_read_data),
        .buf0_node_read_valid(buf0_node_read_valid),
        .buf0_node_read_busy(),
        
        // Buffer1 Node
        .buf1_node_write_start(buf1_node_write_start),
        .buf1_node_write_addr_base(buf1_node_write_addr),
        .buf1_node_write_burst_size(6'd32),
        .buf1_node_write_data(mp_node_output),
        .buf1_node_write_done(buf1_node_write_done),
        .buf1_node_write_busy(),
        
        .buf1_node_read_start(buf1_node_read_start),
        .buf1_node_read_addr_base(buf1_node_read_addr),
        .buf1_node_read_burst_size(6'd32),
        .buf1_node_read_data(buf1_node_read_data),
        .buf1_node_read_valid(buf1_node_read_valid),
        .buf1_node_read_busy(),
        
        // Scatter-Sum In
        .in_ss_node_write_start(in_ss_node_write_start),
        .in_ss_node_write_addr_base(in_ss_node_write_addr),
        .in_ss_node_write_burst_size(6'd32),
        .in_ss_node_write_data(in_ss_node_write_data),
        .in_ss_node_write_done(in_ss_node_write_done),
        .in_ss_node_write_busy(),
        
        .in_ss_node_read_start(in_ss_node_read_start),
        .in_ss_node_read_addr_base(in_ss_node_read_addr),
        .in_ss_node_read_burst_size(6'd32),
        .in_ss_node_read_data(in_ss_node_read_data),
        .in_ss_node_read_valid(in_ss_node_read_valid),
        .in_ss_node_read_busy(),
        
        // Scatter-Sum Out
        .out_ss_node_write_start(out_ss_node_write_start),
        .out_ss_node_write_addr_base(out_ss_node_write_addr),
        .out_ss_node_write_burst_size(6'd32),
        .out_ss_node_write_data(out_ss_node_write_data),
        .out_ss_node_write_done(out_ss_node_write_done),
        .out_ss_node_write_busy(),
        
        .out_ss_node_read_start(out_ss_node_read_start),
        .out_ss_node_read_addr_base(out_ss_node_read_addr),
        .out_ss_node_read_burst_size(6'd32),
        .out_ss_node_read_data(out_ss_node_read_data),
        .out_ss_node_read_valid(out_ss_node_read_valid),
        .out_ss_node_read_busy(),
        
        // Edge Score BRAM (not used in this simplified test)
        .edge_score_write_start(1'b0),
        .edge_score_write_addr_base({ADDR_BITS-5{1'b0}}),
        .edge_score_write_burst_size(1'd1),
        .edge_score_write_data(256'b0),
        .edge_score_write_done(),
        .edge_score_write_busy(),
        
        .edge_score_read_start(1'b0),
        .edge_score_read_addr_base({ADDR_BITS-5{1'b0}}),
        .edge_score_read_burst_size(1'd1),
        .edge_score_read_data(),
        .edge_score_read_valid(),
        .edge_score_read_busy()
    );
    
    // Message Passing Wrapper
    message_passing_wrapper #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS),
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS),
        .NODE_FEATURES(OUT_FEATURES),
        .EDGE_FEATURES(OUT_FEATURES),
        .MAX_EDGES(NUM_EDGES),
        .MAX_NODES(NUM_NODES)
    ) mp_wrapper (
        .clk(clk),
        .rstn(rstn),
        .start(mp_start),
        .done(mp_done),
        
        // Edge Network - Initial Edge Features
        .initial_edge_features(encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_edge_features_re(mp_initial_edge_features_re),
        .initial_edge_features_valid(encoder_edge_read_valid),
        
        // Edge Network - Edge Buffer 0
        .edge_buf0_read_data(buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .edge_buf0_re(mp_edge_buf0_re),
        .edge_buf0_read_valid(buf0_edge_read_valid),
        .edge_buf0_we(mp_edge_buf0_we),
        .edge_buf0_write_done(buf0_edge_write_done),
        
        // Edge Network - Edge Buffer 1
        .edge_buf1_read_data(buf1_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .edge_buf1_re(mp_edge_buf1_re),
        .edge_buf1_read_valid(buf1_edge_read_valid),
        .edge_buf1_we(mp_edge_buf1_we),
        .edge_buf1_write_done(buf1_edge_write_done),
        
        // Edge Network - Initial Node Features
        .initial_node_features_edge(encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_node_features_edge_re(mp_initial_node_features_edge_re),
        .initial_node_features_edge_valid(encoder_node_read_valid),
        
        // Edge Network - Node Buffer 0
        .node_buf0_read_data_edge(buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf0_re_edge(mp_node_buf0_re_edge),
        .node_buf0_read_valid_edge(buf0_node_read_valid),
        
        // Edge Network - Node Buffer 1
        .node_buf1_read_data_edge(buf1_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf1_re_edge(mp_node_buf1_re_edge),
        .node_buf1_read_valid_edge(buf1_node_read_valid),
        
        // Edge Network - Connectivity
        .source_node_index(connectivity_src_data),
        .source_node_index_re(mp_source_node_index_re),
        .source_node_index_valid(1'b1),
        
        .destination_node_index(connectivity_dst_data),
        .destination_node_index_re(mp_destination_node_index_re),
        .destination_node_index_valid(1'b1),
        
        // Edge Network - Outputs
        .edge_address(mp_edge_address),
        .edge_index(mp_edge_index),
        .in_node_index_ss(mp_in_node_index_ss),
        .in_node_ss_write_done(in_ss_node_write_done),
        .out_node_index_ss(mp_out_node_index_ss),
        .scatter_sum_we(mp_scatter_sum_we),
        .out_node_ss_write_done(out_ss_node_write_done),
        .edge_net_node_index(mp_edge_net_node_index),
        .edge_output(mp_edge_output),
        
        // Node Network - Scatter-sum features
        .scatter_sum_features_in(in_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .scatter_sum_features_in_re(mp_scatter_sum_features_in_re),
        .scatter_sum_features_in_valid(in_ss_node_read_valid),
        .scatter_sum_features_in_write_done(in_ss_node_write_done),
        
        .scatter_sum_features_out(out_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .scatter_sum_features_out_re(mp_scatter_sum_features_out_re),
        .scatter_sum_features_out_valid(out_ss_node_read_valid),
        .scatter_sum_features_out_write_done(out_ss_node_write_done),
        
        // Node Network - Node Buffer 0
        .node_buf0_read_data_node(buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf0_re_node(mp_node_buf0_re_node),
        .node_buf0_read_valid_node(buf0_node_read_valid),
        .node_buf0_we(mp_node_buf0_we),
        .node_buf0_write_done(buf0_node_write_done),
        
        // Node Network - Node Buffer 1
        .node_buf1_read_data_node(buf1_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf1_re_node(mp_node_buf1_re_node),
        .node_buf1_read_valid_node(buf1_node_read_valid),
        .node_buf1_we(mp_node_buf1_we),
        .node_buf1_write_done(buf1_node_write_done),
        
        // Node Network - Initial Node Features
        .initial_node_features_node(encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_node_features_node_re(mp_initial_node_features_node_re),
        .initial_node_features_node_valid(encoder_node_read_valid),
        
        // Node Network - Outputs
        .node_address(mp_node_address),
        .node_index(mp_node_index),
        .node_output(mp_node_output)
    );
    
    // ===============================
    // Monitoring for Display Only
    // ===============================
    always @(posedge clk) begin
        if (edge_valid) begin
            $display("[%0t] Edge Encoder: edge %0d encoded", $time, edge_addr_out);
        end
        if (node_valid) begin
            $display("[%0t] Node Encoder: node %0d encoded", $time, node_addr_out);
        end
        if (mp_scatter_sum_we) begin
            $display("[%0t] Edge Network: scatter-sum write (in_idx=%0d, out_idx=%0d)", 
                    $time, mp_in_node_index_ss, mp_out_node_index_ss);
        end
        if (mp_edge_buf0_we || mp_edge_buf1_we) begin
            $display("[%0t] Edge Network: edge %0d processed (write to buf%0d)", 
                    $time, mp_edge_address/OUT_FEATURES, mp_edge_buf1_we ? 1 : 0);
        end
        if (mp_node_buf0_we || mp_node_buf1_we) begin
            $display("[%0t] Node Network: node %0d processed (write to buf%0d)", 
                    $time, mp_node_address/OUT_FEATURES, mp_node_buf1_we ? 1 : 0);
        end
    end
    
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
        $display("STARTING SIMPLIFIED MESSAGE PASSING TEST");
        $display("BLOCK_NUM = %0d (%s)", BLOCK_NUM, IS_EVEN ? "EVEN" : "ODD");
        $display("========================================\n");
        
        // ===============================
        // PHASE 1: Edge Encoding
        // ===============================
        $display("[PHASE 1] Starting edge encoding...");
        edge_start = 1;
        #(CLK_PERIOD*2);
        edge_start = 0;
        
        wait(edge_done);
        $display("[%0t] Edge encoding complete", $time);
        #100;
        
        // ===============================
        // PHASE 2: Node Encoding
        // ===============================
        $display("\n[PHASE 2] Starting node encoding...");
        node_start = 1;
        #(CLK_PERIOD*2);
        node_start = 0;
        
        wait(node_done);
        $display("[%0t] Node encoding complete", $time);
        #100;
        
        // ===============================
        // PHASE 3: Run Message Passing
        // ===============================
        $display("\n[PHASE 3] Running Message Passing...");
        mp_start = 1;
        #(CLK_PERIOD*2);
        mp_start = 0;
        
        wait(mp_done);
        $display("[%0t] Message Passing complete", $time);
        #100;
        
        // ===============================
        // Test Summary
        // ===============================
        $display("\n========================================");
        $display("TEST COMPLETE");
        $display("========================================");
        $display("Edge encoding: DONE");
        $display("Node encoding: DONE");
        $display("Message Passing: DONE");
        $display("========================================\n");
        
        #100;
        $finish;
    end
    
    // ===============================
    // Waveform Dump
    // ===============================
    initial begin
        $dumpfile("message_passing_simplified.vcd");
        $dumpvars(0, tb_message_passing_simplified);
    end

endmodule