`timescale 1ns / 1ps

module tb_simple_edge_storage;

    // Parameters
    parameter CLK_PERIOD = 2;
    parameter NUM_EDGES = 4;
    parameter OUT_FEATURES = 32;
    parameter DATA_BITS = 8;
    parameter ADDR_BITS = 14;
    
    // Clock and Reset
    reg clk = 0;
    reg rst = 1;
    reg rstn = 0;
    
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Test signals
    reg edge_start = 0;
    wire [255:0] edge_data_out;
    wire [13:0] edge_addr_out;
    wire edge_valid;
    wire edge_done;
    
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
    
    // ADDED: Register to preserve edge data for storage write
    reg [255:0] edge_data_out_reg = 0;
    
    // Expected data storage
    reg [255:0] expected_data [0:3];
    integer edge_counter = 0;
    integer read_counter = 0;
    
    // Instantiate DUTs
    edge_encoder #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(6),
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
    
    storage_module #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS),
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(6),
        .MAX_BURST_SIZE(32)
    ) storage (
        .clk(clk),
        .rst(rst),
        .encoder_edge_write_start(storage_write_start),
        .encoder_edge_write_addr_base(storage_write_addr),
        .encoder_edge_write_burst_size(6'd32),
        .encoder_edge_write_data(edge_data_out_reg),  // CHANGED: Use registered data
        .encoder_edge_write_done(storage_write_done),
        .encoder_edge_write_busy(storage_write_busy),
        
        .encoder_edge_read_start(storage_read_start),
        .encoder_edge_read_addr_base(storage_read_addr),
        .encoder_edge_read_burst_size(6'd32),
        .encoder_edge_read_data(storage_read_data),
        .encoder_edge_read_valid(storage_read_valid),
        .encoder_edge_read_busy(storage_read_busy)
    );
    
    // ADDED: Register edge data when valid
    always @(posedge clk) begin
        if (rst) begin
            edge_data_out_reg <= 0;
        end else if (edge_valid) begin
            // Capture edge data when valid
            edge_data_out_reg <= edge_data_out;
            $display("[%0t] Captured edge data for address %0d: %h", 
                    $time, edge_addr_out, edge_data_out);
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
        $display("[%0t] Starting edge encoding...", $time);
        edge_start = 1;
        #20;
        edge_start = 0;
        
        // Monitor and store encoded edges
        fork
            // Monitor encoder output and trigger storage writes
            begin
                while (edge_counter < NUM_EDGES) begin
                    @(posedge clk);
                    if (edge_valid) begin
                        expected_data[edge_addr_out] = edge_data_out;
                        
                        // Start storage write with registered data
                        storage_write_start <= 1;
                        storage_write_addr <= edge_addr_out*OUT_FEATURES*DATA_BITS;
                        @(posedge clk);
                        storage_write_start <= 0;
                        $display("[%0t] Stored edge %0d to BRAM (data: %h)", 
                                $time, edge_addr_out, edge_data_out_reg);
                        // Wait for write completion
                        wait(storage_write_done);
                        
                        edge_counter = edge_counter + 1;
                    end
                end
                $display("[%0t] All edges stored", $time);
            end
            
            // Wait for encoder to finish
            begin
                wait(edge_done);
                $display("[%0t] Edge encoding complete", $time);
            end
        join
        
        #100;
        
        // Verify stored data by reading back
        $display("[%0t] Verifying stored data...", $time);
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
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
                $display("[%0t] Edge %0d: PASS", $time, i);
            end else begin
                $display("[%0t] Edge %0d: FAIL", $time, i);
                $display("  Expected: %h", expected_data[i]);
                $display("  Got: %h", storage_read_data);
            end

            read_counter = read_counter + 1;
            @(posedge clk);  // Extra cycle between reads
        end
        
        $display("[%0t] Test complete. Edges: %0d, Reads: %0d", 
                $time, edge_counter, read_counter);
        
        #100;
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("simple_edge_storage.vcd");
        $dumpvars(0, tb_simple_edge_storage);
    end

endmodule