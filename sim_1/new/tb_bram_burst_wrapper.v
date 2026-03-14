`timescale 1ns/1ps

module tb_bram_burst_wrapper;
    // Parameters from DUT
    parameter RAM_WIDTH = 8;
    parameter RAM_ADDR_BITS = 12;
    parameter MAX_BURST_SIZE = 32;
    parameter DEPTH = 2**RAM_ADDR_BITS;
    
    // Clock and Reset
    reg clock;
    reg reset;
    
    // Burst Write Port
    reg                     write_start;
    reg [RAM_ADDR_BITS-1:0] write_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] write_burst_size;
    reg [RAM_WIDTH*MAX_BURST_SIZE-1:0] write_data;
    wire                   write_done;
    wire                   write_busy;
    
    // Burst Read Port
    reg                     read_start;
    reg [RAM_ADDR_BITS-1:0] read_addr_base;
    reg [$clog2(MAX_BURST_SIZE):0] read_burst_size;
    wire [RAM_WIDTH*MAX_BURST_SIZE-1:0] read_data;
    wire                   read_valid;
    wire                   read_busy;
    
    // DUT Instantiation
    bram_burst_wrapper #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_ADDR_BITS(RAM_ADDR_BITS),
        .MAX_BURST_SIZE(MAX_BURST_SIZE),
        .DATA_FILE(""),
        .INIT_START_ADDR(0),
        .INIT_END_ADDR(0)
    ) dut (
        .clock(clock),
        .reset(reset),
        
        // Burst Write Port
        .write_start(write_start),
        .write_addr_base(write_addr_base),
        .write_burst_size(write_burst_size),
        .write_data(write_data),
        .write_done(write_done),
        .write_busy(write_busy),
        
        // Burst Read Port
        .read_start(read_start),
        .read_addr_base(read_addr_base),
        .read_burst_size(read_burst_size),
        .read_data(read_data),
        .read_valid(read_valid),
        .read_busy(read_busy)
    );
    
    // Clock Generation
    always #5 clock = ~clock;  // 100 MHz clock
    
    // Test Control Variables
    integer error_count;
    integer test_count;
    integer i, j, k;
    
    // Expected data arrays
    reg [RAM_WIDTH-1:0] expected_data_byte [0:MAX_BURST_SIZE-1];
    reg [RAM_WIDTH-1:0] temp_expected_data [0:MAX_BURST_SIZE-1];
    
    // Helper function to convert array to concatenated format (using global array)
    function [RAM_WIDTH*MAX_BURST_SIZE-1:0] array_to_concatenated;
        input integer burst_size;
        reg [RAM_WIDTH*MAX_BURST_SIZE-1:0] result;
        integer idx;
        begin
            result = 0;
            for (idx = 0; idx < burst_size; idx = idx + 1) begin
                result[idx*RAM_WIDTH +: RAM_WIDTH] = temp_expected_data[idx];
            end
            array_to_concatenated = result;
        end
    endfunction
    
    // Helper function to create write data
    function [RAM_WIDTH*MAX_BURST_SIZE-1:0] create_write_data;
        input [RAM_WIDTH-1:0] start_value;
        input integer burst_size;
        integer idx;
        reg [RAM_WIDTH*MAX_BURST_SIZE-1:0] result;
        begin
            result = 0;
            for (idx = 0; idx < burst_size; idx = idx + 1) begin
                result[idx*RAM_WIDTH +: RAM_WIDTH] = start_value + idx;
            end
            create_write_data = result;
        end
    endfunction
    
    // Helper task to verify read data
    task verify_read_data;
        input [RAM_WIDTH*MAX_BURST_SIZE-1:0] actual_data;
        input integer burst_size;
        input [RAM_WIDTH-1:0] expected_start_value;
        integer idx;
        integer local_errors;
        begin
            local_errors = 0;
            for (idx = 0; idx < burst_size; idx = idx + 1) begin
                if (actual_data[idx*RAM_WIDTH +: RAM_WIDTH] !== (expected_start_value + idx)) begin
                    $display("  ERROR: Word %0d - Expected: 0x%h, Got: 0x%h", 
                             idx, (expected_start_value + idx), 
                             actual_data[idx*RAM_WIDTH +: RAM_WIDTH]);
                    local_errors = local_errors + 1;
                end
            end
            if (local_errors > 0) begin
                error_count = error_count + 1;
            end
        end
    endtask
    
    // Main Test Sequence
    initial begin
        // Initialize
        error_count = 0;
        test_count = 0;
        clock = 0;
        reset = 1;
        write_start = 0;
        read_start = 0;
        write_addr_base = 0;
        read_addr_base = 0;
        write_burst_size = 0;
        read_burst_size = 0;
        write_data = 0;
        
        // Initialize arrays
        for (i = 0; i < MAX_BURST_SIZE; i = i + 1) begin
            expected_data_byte[i] = 0;
            temp_expected_data[i] = 0;
        end
        
        // Reset sequence
        #20;
        reset = 0;
        #10;
        
        $display("==========================================");
        $display("Starting BRAM Burst Wrapper Testbench");
        $display("==========================================");
        
        // ========================================
        // TEST 1: Single Word Write and Read
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Single Word Write and Read", test_count);
        
        // Write single word
        write_start = 1;
        write_addr_base = 16'h0100;
        write_burst_size = 1;
        write_data = create_write_data(8'hAA, 1);
        
        #10;
        write_start = 0;
        
        // Wait for write to complete
        wait(write_done == 1);
        #10;
        
        // Read back the same word
        read_start = 1;
        read_addr_base = 16'h0100;
        read_burst_size = 1;
        
        #10;
        read_start = 0;
        
        // Wait for read to complete
        wait(read_valid == 1);
        #10;
        
        // Verify read data
        if (read_data[RAM_WIDTH-1:0] !== 8'hAA) begin
            $display("ERROR: Test %0d failed. Expected: 0x%h, Got: 0x%h", 
                     test_count, 8'hAA, read_data[RAM_WIDTH-1:0]);
            error_count = error_count + 1;
        end else begin
            $display("Test %0d passed.", test_count);
        end
        
        // ========================================
        // TEST 2: Maximum Burst Write and Read
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Maximum Burst (%0d words)", test_count, MAX_BURST_SIZE);
        
        // Prepare expected data in global array
        for (i = 0; i < MAX_BURST_SIZE; i = i + 1) begin
            temp_expected_data[i] = 8'h10 + i;
        end
        
        // Write maximum burst
        write_start = 1;
        write_addr_base = 16'h0200;
        write_burst_size = MAX_BURST_SIZE;
        write_data = create_write_data(8'h10, MAX_BURST_SIZE);
        
        #10;
        write_start = 0;
        
        // Wait for write to complete
        wait(write_done == 1);
        #10;
        
        // Read back the burst
        read_start = 1;
        read_addr_base = 16'h0200;
        read_burst_size = MAX_BURST_SIZE;
        
        #10;
        read_start = 0;
        
        // Wait for read to complete
        wait(read_valid == 1);
        #10;
        
        // Verify read data
        $display("Verifying burst data...");
        verify_read_data(read_data, MAX_BURST_SIZE, 8'h10);
        
        if (error_count < test_count) begin
            $display("Test %0d passed.", test_count);
        end
        
        // ========================================
        // TEST 3: Small Burst Write and Read
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Small Burst (8 words)", test_count);
        
        // Write 8 words
        write_start = 1;
        write_addr_base = 16'h0300;
        write_burst_size = 8;
        write_data = create_write_data(8'h80, 8);
        
        #10;
        write_start = 0;
        
        // Wait for write to complete
        wait(write_done == 1);
        #10;
        
        // Read back the burst
        read_start = 1;
        read_addr_base = 16'h0300;
        read_burst_size = 8;
        
        #10;
        read_start = 0;
        
        // Wait for read to complete
        wait(read_valid == 1);
        #10;
        
        // Verify read data
        $display("Verifying small burst data...");
        verify_read_data(read_data, 8, 8'h80);
        
        if (error_count < test_count) begin
            $display("Test %0d passed.", test_count);
        end
        
        // ========================================
        // TEST 4: Concurrent Write and Read Operations
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Concurrent Operations", test_count);
        
        // Start a write operation
        write_start = 1;
        write_addr_base = 16'h0400;
        write_burst_size = 16;
        write_data = create_write_data(8'hC0, 16);
        
        #10;
        write_start = 0;
        
        // Start a read operation from different address while write is busy
        #20;
        read_start = 1;
        read_addr_base = 16'h0100;  // Address from Test 1
        read_burst_size = 1;
        
        #10;
        read_start = 0;
        
        // Wait for both operations to complete
        fork
            begin
                wait(write_done == 1);
                $display("Write operation completed");
            end
            begin
                wait(read_valid == 1);
                $display("Read operation completed");
                // Verify the read data (should still be from Test 1)
                if (read_data[RAM_WIDTH-1:0] !== 8'hAA) begin
                    $display("ERROR: Test %0d failed during concurrent ops. Expected: 0x%h, Got: 0x%h",
                             test_count, 8'hAA, read_data[RAM_WIDTH-1:0]);
                    error_count = error_count + 1;
                end
            end
        join
        
        #10;
        
        if (error_count < test_count) begin
            $display("Test %0d passed.", test_count);
        end
        
        // ========================================
        // TEST 5: Back-to-Back Operations
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Back-to-Back Operations", test_count);
        
        // Write first burst
        write_start = 1;
        write_addr_base = 16'h0500;
        write_burst_size = 4;
        write_data = create_write_data(8'hF0, 4);
        
        #10;
        write_start = 0;
        
        // Start second write immediately after first completes
        @(posedge write_done);
        #5;
        write_start = 1;
        write_addr_base = 16'h0600;
        write_burst_size = 4;
        write_data = create_write_data(8'hE0, 4);
        
        #10;
        write_start = 0;
        
        // Wait for second write to complete
        wait(write_done == 1);
        #10;
        
        // Read both bursts
        read_start = 1;
        read_addr_base = 16'h0500;
        read_burst_size = 4;
        
        #10;
        read_start = 0;
        
        wait(read_valid == 1);
        #10;
        
        // Verify first read
        $display("Verifying first burst...");
        verify_read_data(read_data, 4, 8'hF0);
        
        // Read second burst
        read_start = 1;
        read_addr_base = 16'h0600;
        read_burst_size = 4;
        
        #10;
        read_start = 0;
        
        wait(read_valid == 1);
        #10;
        
        // Verify second read
        $display("Verifying second burst...");
        verify_read_data(read_data, 4, 8'hE0);
        
        if (error_count < test_count) begin
            $display("Test %0d passed.", test_count);
        end
        
        // ========================================
        // TEST 6: Invalid Burst Size Handling
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Invalid Burst Size Handling", test_count);
        
        // Try to write with burst size 0 (should not start)
        write_start = 1;
        write_addr_base = 16'h0700;
        write_burst_size = 0;
        write_data = 0;
        
        #10;
        write_start = 0;
        
        #50;  // Wait longer than normal operation
        
        if (write_busy !== 0) begin
            $display("ERROR: Test %0d failed. Write busy when burst size is 0", test_count);
            error_count = error_count + 1;
        end else begin
            $display("Test %0d passed: Correctly ignored burst size 0", test_count);
        end
        
        // Try to write with burst size > MAX_BURST_SIZE
        #10;
        write_start = 1;
        write_addr_base = 16'h0800;
        write_burst_size = MAX_BURST_SIZE + 1;
        write_data = 0;
        
        #10;
        write_start = 0;
        
        #50;
        
        if (write_busy !== 0) begin
            $display("ERROR: Test %0d failed. Write busy when burst size > MAX", test_count);
            error_count = error_count + 1;
        end else begin
            $display("Test %0d passed: Correctly ignored burst size > MAX", test_count);
        end
        
        // ========================================
        // TEST 7: Reset During Operation
        // ========================================
        test_count = test_count + 1;
        $display("\nTest %0d: Reset During Operation", test_count);
        
        // Start a long write operation
        write_start = 1;
        write_addr_base = 16'h0900;
        write_burst_size = MAX_BURST_SIZE;
        write_data = create_write_data(8'h90, MAX_BURST_SIZE);
        
        #10;
        write_start = 0;
        
        // Apply reset in the middle of operation
        #30;
        reset = 1;
        #20;
        reset = 0;
        
        // Wait to see if operation is properly aborted
        #50;
        
        if (write_busy === 0 && read_busy === 0) begin
            $display("Test %0d passed: Reset properly aborted operations", test_count);
        end else begin
            $display("ERROR: Test %0d failed. Modules still busy after reset", test_count);
            error_count = error_count + 1;
        end
        
        // ========================================
        // Test Summary
        // ========================================
        #100;
        $display("\n==========================================");
        $display("Test Summary:");
        $display("Total Tests Run: %0d", test_count);
        // Calculate actual errors (not counting previous test failures)
        $display("==========================================");
        
        #100;
        $finish;
    end
    
    // Monitor for signals (optional for debugging)
    always @(posedge clock) begin
        if (write_start) begin
            $display("[%0t] Write started: addr=0x%h, size=%0d", $time, write_addr_base, write_burst_size);
        end
        if (write_done) begin
            $display("[%0t] Write completed", $time);
        end
        if (read_start) begin
            $display("[%0t] Read started: addr=0x%h, size=%0d", $time, read_addr_base, read_burst_size);
        end
        if (read_valid) begin
            $display("[%0t] Read completed, data valid", $time);
        end
    end
    
    // Waveform dump for debugging
    initial begin
        $dumpfile("tb_bram_burst_wrapper.vcd");
        $dumpvars(0, tb_bram_burst_wrapper);
        // Add more signals if needed for debugging
        $dumpvars(1, dut);
    end
    
endmodule