`timescale 1ns / 1ps

module storage_module_tb;

    // Parameters matching the module
    parameter DATA_BITS = 8;
    parameter RAM_ADDR_BITS_FOR_NODE = 16;
    parameter RAM_ADDR_BITS_FOR_EDGE = 12;
    parameter NUM_NODES = 16;
    parameter NUM_EDGES = 32;
    parameter NUM_FEATURES = 4;
    parameter MAX_BURST_SIZE = 32;

    // Clock and Reset
    reg clk;
    reg rst;
    
    // Connectivity interface signals
    reg connectivity_src_re;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] connectivity_src_addr;
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] connectivity_src_data;
    
    reg connectivity_dst_re;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] connectivity_dst_addr;
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] connectivity_dst_data;
    
    // Dummy signals for other interfaces (not used in this test)
    reg encoder_edge_write_start;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] encoder_edge_write_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] encoder_edge_write_burst_size;
    reg [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_write_data;
    wire encoder_edge_write_done;
    wire encoder_edge_write_busy;
    
    reg encoder_edge_read_start;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] encoder_edge_read_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] encoder_edge_read_burst_size;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_read_data;
    wire encoder_edge_read_valid;
    wire encoder_edge_read_busy;
    
    reg encoder_node_write_start;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] encoder_node_write_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] encoder_node_write_burst_size;
    reg [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_write_data;
    wire encoder_node_write_done;
    wire encoder_node_write_busy;
    
    reg encoder_node_read_start;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] encoder_node_read_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] encoder_node_read_burst_size;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_read_data;
    wire encoder_node_read_valid;
    wire encoder_node_read_busy;
    
    // Testbench variables
    integer error_count;
    integer test_pass_count;
    integer test_fail_count;
    
    // Memory content for verification
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] expected_src_data [0:NUM_EDGES-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] expected_dst_data [0:NUM_EDGES-1];
    
    // Clock generation
    always #5 clk = ~clk;  // 100MHz clock (10ns period)
    
    // Instantiate the DUT
    storage_module #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(RAM_ADDR_BITS_FOR_NODE),
        .RAM_ADDR_BITS_FOR_EDGE(RAM_ADDR_BITS_FOR_EDGE),
        .NUM_NODES(NUM_NODES),
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(NUM_FEATURES),
        .MAX_BURST_SIZE(MAX_BURST_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        
        // Connectivity interfaces (the ones we're testing)
        .connectivity_src_re(connectivity_src_re),
        .connectivity_src_addr(connectivity_src_addr),
        .connectivity_src_data(connectivity_src_data),
        
        .connectivity_dst_re(connectivity_dst_re),
        .connectivity_dst_addr(connectivity_dst_addr),
        .connectivity_dst_data(connectivity_dst_data),
        
        // Other interfaces (tied off)
        .encoder_edge_write_start(1'b0),
        .encoder_edge_write_addr_base(0),
        .encoder_edge_write_burst_size(0),
        .encoder_edge_write_data(0),
        .encoder_edge_write_done(),
        .encoder_edge_write_busy(),
        
        .encoder_edge_read_start(1'b0),
        .encoder_edge_read_addr_base(0),
        .encoder_edge_read_burst_size(0),
        .encoder_edge_read_data(),
        .encoder_edge_read_valid(),
        .encoder_edge_read_busy(),
        
        .encoder_node_write_start(1'b0),
        .encoder_node_write_addr_base(0),
        .encoder_node_write_burst_size(0),
        .encoder_node_write_data(0),
        .encoder_node_write_done(),
        .encoder_node_write_busy(),
        
        .encoder_node_read_start(1'b0),
        .encoder_node_read_addr_base(0),
        .encoder_node_read_burst_size(0),
        .encoder_node_read_data(),
        .encoder_node_read_valid(),
        .encoder_node_read_busy()
    );
    
    // Task to check source connectivity data
    task check_src_data;
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] addr;
    input [RAM_ADDR_BITS_FOR_NODE-1:0] expected_value;
    begin
        // Set up address BEFORE clock edge
        connectivity_src_addr = addr;
        
        // Assert read enable AFTER current clock edge
        @(posedge clk);
        #1;  // Small delay after clock edge
        connectivity_src_re = 1'b1;
        
        // Deassert AFTER next clock edge
        @(posedge clk);
        #1;  // Small delay after clock edge
        connectivity_src_re = 1'b0;
        
        // Wait for BRAM read latency (1 cycle)
        @(posedge clk);
        #1;  // Sample data after clock edge
        
        if (connectivity_src_data !== expected_value) begin
            $display("[ERROR] Time=%0t: Source connectivity addr=%0d: Expected=0x%0h, Got=0x%0h", 
                     $time, addr, expected_value, connectivity_src_data);
            error_count = error_count + 1;
            test_fail_count = test_fail_count + 1;
        end else begin
            $display("[PASS]  Time=%0t: Source connectivity addr=%0d: Value=0x%0h", 
                     $time, addr, connectivity_src_data);
            test_pass_count = test_pass_count + 1;
        end
        
        // Add a cycle between checks
        @(posedge clk);
    end
endtask
    
    // Task to check destination connectivity data
    task check_dst_data;
        input [RAM_ADDR_BITS_FOR_EDGE-1:0] addr;
        input [RAM_ADDR_BITS_FOR_NODE-1:0] expected_value;
        begin
            connectivity_dst_addr = addr;
            connectivity_dst_re = 1'b1;
            @(posedge clk);
            connectivity_dst_re = 1'b0;
            
            // Wait for data (BRAM should have 1-cycle read latency)
            @(posedge clk);
            
            if (connectivity_dst_data !== expected_value) begin
                $display("[ERROR] Time=%0t: Destination connectivity addr=%0d: Expected=0x%0h, Got=0x%0h", 
                         $time, addr, expected_value, connectivity_dst_data);
                error_count = error_count + 1;
                test_fail_count = test_fail_count + 1;
            end else begin
                $display("[PASS]  Time=%0t: Destination connectivity addr=%0d: Value=0x%0h", 
                         $time, addr, connectivity_dst_data);
                test_pass_count = test_pass_count + 1;
            end
            @(posedge clk); // Add a cycle between checks
        end
    endtask
    
    // Task to check simultaneous read from both BRAMs
    task check_simultaneous_read;
        input [RAM_ADDR_BITS_FOR_EDGE-1:0] src_addr;
        input [RAM_ADDR_BITS_FOR_NODE-1:0] src_expected;
        input [RAM_ADDR_BITS_FOR_EDGE-1:0] dst_addr;
        input [RAM_ADDR_BITS_FOR_NODE-1:0] dst_expected;
        begin
            connectivity_src_addr = src_addr;
            connectivity_src_re = 1'b1;
            connectivity_dst_addr = dst_addr;
            connectivity_dst_re = 1'b1;
            @(posedge clk);
            connectivity_src_re = 1'b0;
            connectivity_dst_re = 1'b0;
            
            // Wait for data
            @(posedge clk);
            
            // Check source
            if (connectivity_src_data !== src_expected) begin
                $display("[ERROR] Time=%0t: Simultaneous read - Source addr=%0d: Expected=0x%0h, Got=0x%0h", 
                         $time, src_addr, src_expected, connectivity_src_data);
                error_count = error_count + 1;
                test_fail_count = test_fail_count + 1;
            end else begin
                $display("[PASS]  Time=%0t: Simultaneous read - Source addr=%0d: Value=0x%0h", 
                         $time, src_addr, connectivity_src_data);
                test_pass_count = test_pass_count + 1;
            end
            
            // Check destination
            if (connectivity_dst_data !== dst_expected) begin
                $display("[ERROR] Time=%0t: Simultaneous read - Destination addr=%0d: Expected=0x%0h, Got=0x%0h", 
                         $time, dst_addr, dst_expected, connectivity_dst_data);
                error_count = error_count + 1;
                test_fail_count = test_fail_count + 1;
            end else begin
                $display("[PASS]  Time=%0t: Simultaneous read - Destination addr=%0d: Value=0x%0h", 
                         $time, dst_addr, connectivity_dst_data);
                test_pass_count = test_pass_count + 1;
            end
            @(posedge clk); // Add a cycle between checks
        end
    endtask
    
    // Initialize test
    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        connectivity_src_re = 0;
        connectivity_src_addr = 0;
        connectivity_dst_re = 0;
        connectivity_dst_addr = 0;
        error_count = 0;
        test_pass_count = 0;
        test_fail_count = 0;
        
//         Expected source data
//         11001000
// 11001001100011
// 1100110011
// 10000110011111
// 10011010000
// 10110010110111
// 10001101101001
// 101010001000
// 101111110001101
// 110110001000010
// 1111010000
// 100010101100
// 100000010001000
// 1000010100111
// 1100010110
// 100000010000111
// 100000010000111
// 11011000010010
// 10110000001111
// 1100001000101
// 1000010111011
// 111011001
// 10001000111100
// 10100011011101
// 100011101001
// 11001000110101
// 10100100100100
// 1010010101
// 100000111001101
// 101111100100011
// 10101001010011
// 1111001101010
        // Initialize expected_src_data array with 18-bit binary values for all 32 entries
expected_src_data[0]  = 18'b0000000000011001000;     // "11001000" padded to 18 bits
expected_src_data[1]  = 18'b000011001001100011;      // "11001001100011" padded to 18 bits  
expected_src_data[2]  = 18'b00000000001100110011;    // "1100110011" padded to 18 bits
expected_src_data[3]  = 18'b00010000110011111;       // "10000110011111" padded to 18 bits 10000110011111 
expected_src_data[4]  = 18'b000000010011010000;      // "10011010000" padded to 18 bits
expected_src_data[5]  = 18'b00101100101101111;       // "10110010110111" padded to 18 bits
expected_src_data[6]  = 18'b00100011011010011;       // "10001101101001" padded to 18 bits
expected_src_data[7]  = 18'b00000101010001000;       // "101010001000" padded to 18 bits
expected_src_data[8]  = 18'b0101111110001101;        // "101111110001101" padded to 18 bits
expected_src_data[9]  = 18'b0110110001000010;        // "110110001000010" padded to 18 bits
expected_src_data[10] = 18'b0000001111010000;        // "1111010000" padded to 18 bits
expected_src_data[11] = 18'b00000100010101100;       // "100010101100" padded to 18 bits
expected_src_data[12] = 18'b0100000010001000;        // "100000010001000" padded to 18 bits
expected_src_data[13] = 18'b00010000010100111;       // "1000010100111" padded to 18 bits
expected_src_data[14] = 18'b0000001100010110;        // "1100010110" padded to 18 bits
expected_src_data[15] = 18'b0100000010000111;        // "100000010000111" padded to 18 bits
expected_src_data[16] = 18'b0100000010000111;        // "100000010000111" padded to 18 bits
expected_src_data[17] = 18'b0011011000010010;        // "11011000010010" padded to 18 bits
expected_src_data[18] = 18'b0010110000001111;        // "10110000001111" padded to 18 bits
expected_src_data[19] = 18'b0001100001000101;        // "1100001000101" padded to 18 bits
expected_src_data[20] = 18'b0001000010111011;        // "1000010111011" padded to 18 bits
expected_src_data[21] = 18'b0000000111011001;        // "111011001" padded to 18 bits
expected_src_data[22] = 18'b0010001000111100;        // "10001000111100" padded to 18 bits
expected_src_data[23] = 18'b0010100011011101;        // "10100011011101" padded to 18 bits
expected_src_data[24] = 18'b00000100011101001;       // "100011101001" padded to 18 bits
expected_src_data[25] = 18'b011001000110101;         // "11001000110101" padded to 18 bits
expected_src_data[26] = 18'b0010100100100100;        // "10100100100100" padded to 18 bits
expected_src_data[27] = 18'b000001010010101;         // "1010010101" padded to 18 bits
expected_src_data[28] = 18'b0100000111001101;        // "100000111001101" padded to 18 bits
expected_src_data[29] = 18'b0101111100100011;        // "101111100100011" padded to 18 bits
expected_src_data[30] = 18'b0010101001010011;        // "10101001010011" padded to 18 bits
expected_src_data[31] = 18'b0001111001101010;        // "1111001101010" padded to 18 bits

        expected_dst_data[0]  = 18'b00100011100100010;
expected_dst_data[1]  = 18'b01010000100100100;
expected_dst_data[2]  = 18'b000100100010110010;
expected_dst_data[3]  = 18'b0010001000111100;
expected_dst_data[4]  = 18'b0100011101100010;
expected_dst_data[5]  = 18'b1011101011011000;
expected_dst_data[6]  = 18'b00010001110111010;
expected_dst_data[7]  = 18'b00101010101000000;
expected_dst_data[8]  = 18'b1100100101110101;
expected_dst_data[9]  = 18'b11011111110111100;
expected_dst_data[10] = 18'b000100101001011010;
expected_dst_data[11] = 18'b00100111010010011;
expected_dst_data[12] = 18'b00010000011010100;
expected_dst_data[13] = 18'b00110000101100001;
expected_dst_data[14] = 18'b00100001010110010;
expected_dst_data[15] = 18'b100000011010100;
expected_dst_data[16] = 18'b0100000011010101;
expected_dst_data[17] = 18'b00011100111111011;
expected_dst_data[18] = 18'b000010110001010001;
expected_dst_data[19] = 18'b000001110001000110;
expected_dst_data[20] = 18'b00110000101100001;
expected_dst_data[21] = 18'b00100000110000001;
expected_dst_data[22] = 18'b01000001001010111;
expected_dst_data[23] = 18'b0010100101100101;
expected_dst_data[24] = 18'b00100111010010011;
expected_dst_data[25] = 18'b01010000100100100;
expected_dst_data[26] = 18'b0010100101100101;
expected_dst_data[27] = 18'b000100100010110010;
expected_dst_data[28] = 18'b00100001000100100;
expected_dst_data[29] = 18'b11011101111011101;
expected_dst_data[30] = 18'b1011101011011000;
expected_dst_data[31] = 18'b0111010010011000;





        $display("=========================================");
        $display("Starting testbench for connectivity BRAMs");
        $display("NUM_EDGES = %0d", NUM_EDGES);
        $display("NUM_NODES = %0d", NUM_NODES);
        $display("RAM_ADDR_BITS_FOR_NODE = %0d", RAM_ADDR_BITS_FOR_NODE);
        $display("=========================================\n");
        
        // Apply reset
        #20;
        rst = 0;
        #10;
        
        $display("\n[TEST 1]: Testing source connectivity BRAM reads...");
        // Test sequential reads from source connectivity BRAM
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            if (i < 5 || i >= NUM_EDGES-5 || i % 8 == 0) begin
                check_src_data(i, expected_src_data[i]);
            end
        end
        
        // Test some boundary cases
        $display("\n[TEST 2]: Testing boundary addresses for source BRAM...");
        check_src_data(0, expected_src_data[0]);
        check_src_data(NUM_EDGES-1, expected_src_data[NUM_EDGES-1]);
        
        $display("\n[TEST 3]: Testing destination connectivity BRAM reads...");
        // Test sequential reads from destination connectivity BRAM
        for (integer i = 0; i < NUM_EDGES; i = i + 1) begin
            if (i < 5 || i >= NUM_EDGES-5 || i % 8 == 0) begin
                check_dst_data(i, expected_dst_data[i]);
            end
        end
        
        // Test some boundary cases
        $display("\n[TEST 4]: Testing boundary addresses for destination BRAM...");
        check_dst_data(0, expected_dst_data[0]);
        check_dst_data(NUM_EDGES-1, expected_dst_data[NUM_EDGES-1]);
        
        $display("\n[TEST 5]: Testing simultaneous reads from both BRAMs...");
        // Test reading from both BRAMs at the same time
        check_simultaneous_read(0, expected_src_data[0], 
                                0, expected_dst_data[0]);
        check_simultaneous_read(10, expected_src_data[10], 
                                20, expected_dst_data[20]);
        check_simultaneous_read(NUM_EDGES-1, expected_src_data[NUM_EDGES-1],
                                NUM_EDGES-1, expected_dst_data[NUM_EDGES-1]);
        
        $display("\n[TEST 6]: Testing random address reads...");
        // Test random addresses
        check_src_data(7, expected_src_data[7]);
        check_dst_data(15, expected_dst_data[15]);
        check_src_data(23, expected_src_data[23]);
        check_dst_data(31, expected_dst_data[31]);
        
    
        
        // Wait a few cycles
        #100;
        
        // Print summary
        $display("\n=========================================");
        $display("TEST SUMMARY");
        $display("=========================================");
        $display("Total tests passed: %0d", test_pass_count);
        $display("Total tests failed: %0d", test_fail_count);
        $display("Total errors: %0d", error_count);
        
        if (error_count == 0) begin
            $display("\n[SUCCESS] All connectivity BRAM tests passed!");
        end else begin
            $display("\n[FAILURE] %0d test(s) failed!", error_count);
        end
        $display("=========================================\n");
        
        $finish;
    end
    
    // Monitor signals
    initial begin
        $monitor("Time=%0t: src_re=%b, src_addr=%0d, src_data=0x%0h, dst_re=%b, dst_addr=%0d, dst_data=0x%0h",
                 $time, connectivity_src_re, connectivity_src_addr, connectivity_src_data,
                 connectivity_dst_re, connectivity_dst_addr, connectivity_dst_data);
    end
    
    // Generate VCD file for waveform viewing
    initial begin
        $dumpfile("storage_module_tb.vcd");
        $dumpvars(0, storage_module_tb);
    end
    
endmodule