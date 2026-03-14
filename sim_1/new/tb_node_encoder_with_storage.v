`timescale 1ns / 1ps

module tb_simple_node_storage;

    // Parameters
    parameter CLK_PERIOD = 2;
    parameter NUM_NODES = 4;
    parameter OUT_FEATURES = 32;
    parameter DATA_BITS = 8;
    parameter ADDR_BITS = 14;
    
    // Clock and Reset
    reg clk = 0;
    reg rst = 1;
    reg rstn = 0;
    
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Test signals
    reg node_start = 0;
    wire [255:0] node_data_out;
    wire [13:0] node_addr_out;
    wire node_valid;
    wire node_done;
    
    // Storage signals
    reg storage_write_start = 0;
    reg [13:0] storage_write_addr = 0;
    reg storage_read_start = 0;
    reg [13:0] storage_read_addr = 0;
    wire [255:0] storage_read_data;
    wire storage_read_valid;
    wire storage_write_done;
    wire storage_write_busy;
    wire storage_read_busy;
    
    // ADDED: Register to preserve node data for storage write
    reg [255:0] node_data_out_reg = 0;
    
    // Expected data storage
    reg [255:0] expected_data [0:3];
    integer node_counter = 0;
    integer read_counter = 0;
    
    // Instantiate DUTs
    node_encoder #(
        .NUM_NODES(NUM_NODES),
        .NUM_FEATURES(12),
        .DATA_BITS(DATA_BITS),
        .OUT_FEATURES(OUT_FEATURES),
        .MEM_FILE("node_initial_features.mem")
    ) encoder (
        .clk(clk),
        .rstn(rstn),
        .start(node_start),
        .encoded_data(node_data_out),
        .node_addr_out(node_addr_out),
        .data_valid(node_valid),
        .done(node_done)
    );
    
    storage_module #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(ADDR_BITS),
        .NUM_NODES(NUM_NODES),
        .NUM_FEATURES(12),
        .MAX_BURST_SIZE(32)
    ) storage (
        .clk(clk),
        .rst(rst),
        .encoder_node_write_start(storage_write_start),
        .encoder_node_write_addr_base(storage_write_addr),
        .encoder_node_write_burst_size(32),
        .encoder_node_write_data(node_data_out_reg),  // CHANGED: Use registered data
        .encoder_node_write_done(storage_write_done),
        .encoder_node_write_busy(storage_write_busy),
        
        .encoder_node_read_start(storage_read_start),
        .encoder_node_read_addr_base(storage_read_addr),
        .encoder_node_read_burst_size(32),
        .encoder_node_read_data(storage_read_data),
        .encoder_node_read_valid(storage_read_valid),
        .encoder_node_read_busy(storage_read_busy)
    );
    
    // ADDED: Register node data when valid
    always @(posedge clk) begin
        if (rst) begin
            node_data_out_reg <= 0;
        end else if (node_valid) begin
            // Capture node data when valid
            node_data_out_reg <= node_data_out;
            $display("[%0t] Captured node data for address %0d: %h", 
                    $time, node_addr_out, node_data_out);
        end
    end
    
    // Test sequence
    initial begin
        // Reset
        #100;
        rst = 0;
        rstn = 1;
        #100;
        
        // Start encoding
        $display("[%0t] Starting node encoding...", $time);
        node_start = 1;
        #20;
        node_start = 0;
        
        // Monitor and store encoded nodes
        fork
            // Monitor encoder output and trigger storage writes
            begin
                while (node_counter < NUM_NODES) begin
                    @(posedge clk);
                    if (node_valid) begin
                        expected_data[node_addr_out] = node_data_out;
                        
                        // Start storage write with registered data
                        storage_write_start <= 1;
                        storage_write_addr <= node_addr_out*OUT_FEATURES*DATA_BITS;
                        @(posedge clk);
                        storage_write_start <= 0;
                        $display("[%0t] Stored node %0d to BRAM (data: %h)", 
                                $time, node_addr_out, node_data_out_reg);
                        // Wait for write completion
                        wait(storage_write_done);
                        
                        node_counter = node_counter + 1;
                    end
                end
                $display("[%0t] All nodes stored", $time);
            end
            
            // Wait for encoder to finish
            begin
                wait(node_done);
                $display("[%0t] node encoding complete", $time);
            end
        join
        
        #100;
        
        // Verify stored data by reading back
        $display("[%0t] Verifying stored data...", $time);
        for (integer i = 0; i < NUM_NODES; i = i + 1) begin
            // Start read for current address
            @(posedge clk);
            storage_read_start = 1;
            storage_read_addr = i*OUT_FEATURES*DATA_BITS;

            @(posedge clk);
            storage_read_start = 0;

            // Wait for read completion
            wait(storage_read_valid);
            @(posedge clk);

            if (storage_read_data == expected_data[i]) begin
                $display("[%0t] Node %0d: PASS", $time, i);
            end else begin
                $display("[%0t] Node %0d: FAIL", $time, i);
                $display("  Expected: %h", expected_data[i]);
                $display("  Got: %h", storage_read_data);
            end

            read_counter = read_counter + 1;
            @(posedge clk);  // Extra cycle between reads
        end
        
        $display("[%0t] Test complete. Nodes: %0d, Reads: %0d", 
                $time, node_counter, read_counter);
        
        #100;
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("simple_node_storage.vcd");
        $dumpvars(0, tb_simple_node_storage);
    end

endmodule