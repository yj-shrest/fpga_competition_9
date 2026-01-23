module test_node_encoder;
    reg clk = 0;
    reg rstn = 0;
    reg start = 0;
    wire done;
    wire [255:0] encoded_data;  // 32 × 8 bits
    wire [13:0] node_addr_out;
    wire data_valid;
    
    node_encoder #(
        .NUM_NODES(4),
        .NUM_FEATURES(12),
        .DATA_BITS(8),
        .OUT_FEATURES(32),
        .MEM_FILE("node_initial_features.mem")
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .encoded_data(encoded_data),
        .node_addr_out(node_addr_out),
        .data_valid(data_valid),
        .done(done)
    );
    
    // Clock generation
    always #5 clk = ~clk;
    
    initial begin
        // Reset
        rstn = 0;
        #20 rstn = 1;
        
        // Wait for memory initialization
        #10;
        
        // Start processing
        start = 1;
        #10 start = 0;
        
        // Wait for completion
        wait(done);
        
        #100;
        $display("Simulation complete");
        $finish;
    end
    
    // Monitor output
    always @(posedge clk) begin
        if (data_valid) begin
            $display("Time %0t: node %0d encoded: %h", 
                    $time, node_addr_out, encoded_data);
        end
    end
endmodule