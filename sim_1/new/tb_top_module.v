`timescale 1ns / 1ps

module tb_top_module;

    // Parameters - match those in the top module
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
    
    // Testbench signals
    reg clk;
    reg rstn;
    wire processing_done;
    wire [3:0] current_phase;
    
    // Phase names for display
    reg [255:0] phase_name;
    
    // Test monitoring
    integer test_pass = 0;
    integer cycle_count = 0;
    
    // ===============================
    // Clock Generation
    // ===============================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ===============================
    // DUT Instantiation
    // ===============================
    top_module #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_NODES(NUM_NODES),
        .NUM_FEATURES(NUM_FEATURES),
        .OUT_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS),
        .ADDR_BITS(ADDR_BITS),
        .NODE_ADDR_BITS(NODE_ADDR_BITS),
        .MAX_BURST_SIZE(MAX_BURST_SIZE)
        ) dut (
        .clk(clk),
        .rstn(rstn),
        .processing_done(processing_done),
        .current_phase(current_phase)
    );
    
    // ===============================
    // Phase Name Decoder
    // ===============================
    always @(*) begin
        case (current_phase)
            4'd0: phase_name = "IDLE";
            4'd1: phase_name = "EDGE_ENCODE";
            4'd2: phase_name = "EDGE_ENCODE_WAIT";
            4'd3: phase_name = "NODE_ENCODE";
            4'd4: phase_name = "NODE_ENCODE_WAIT";
            4'd5: phase_name = "MESSAGE_PASSING";
            4'd6: phase_name = "MESSAGE_PASSING_WAIT";
            4'd7: phase_name = "EDGE_DECODE";
            4'd8: phase_name = "EDGE_DECODE_WAIT";
            4'd9: phase_name = "DONE";
            default: phase_name = "UNKNOWN";
        endcase
    end
    
    // ===============================
    // Cycle Counter
    // ===============================
    always @(posedge clk) begin
        if (!rstn)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // ===============================
    // Phase Transition Monitor
    // ===============================
    reg [3:0] prev_phase;
    always @(posedge clk) begin
        if (!rstn) begin
            prev_phase <= 4'd0;
        end else begin
            if (current_phase != prev_phase) begin
                $display("[%0t] [Cycle %0d] Phase Transition: %0s -> %0s", 
                         $time, cycle_count, 
                         get_phase_name(prev_phase), 
                         get_phase_name(current_phase));
                prev_phase <= current_phase;
            end
        end
    end
    
    // ===============================
    // Processing Done Monitor
    // ===============================
    always @(posedge clk) begin
        if (processing_done && !$test$plusargs("quiet")) begin
            $display("[%0t] [Cycle %0d] *** PROCESSING COMPLETE ***", $time, cycle_count);
        end
    end
    
    // ===============================
    // Test Sequence
    // ===============================
    initial begin
        // Initialize signals
        rstn = 0;
        
        // Print test header
        $display("\n========================================");
        $display("MESSAGE PASSING TOP MODULE TESTBENCH");
        $display("========================================");
        $display("Parameters:");
        $display("  NUM_EDGES       = %0d", NUM_EDGES);
        $display("  NUM_NODES       = %0d", NUM_NODES);
        $display("  NUM_FEATURES    = %0d", NUM_FEATURES);
        $display("  OUT_FEATURES    = %0d", OUT_FEATURES);
        $display("  DATA_BITS       = %0d", DATA_BITS);
        $display("  BLOCK_NUM       = %0d", BLOCK_NUM);
        $display("========================================\n");
        
        // Hold reset for initial period
        $display("[%0t] Applying reset...", $time);
        #(CLK_PERIOD * 20);
        
        // Release reset
        $display("[%0t] Releasing reset...", $time);
        rstn = 1;
        #(CLK_PERIOD * 2);
        
        $display("[%0t] System started - waiting for completion...\n", $time);
        
        // Wait for processing to complete
        wait(processing_done);
        
        // Give some time after completion
        #(CLK_PERIOD * 20);
        
        // Print summary
        $display("\n========================================");
        $display("TEST COMPLETE");
        $display("========================================");
        $display("Total clock cycles: %0d", cycle_count);
        $display("Total time: %0t", $time);
        $display("Status: %0s", processing_done ? "PASS - All phases completed" : "FAIL");
        $display("========================================\n");
        
        if (processing_done) begin
            $display("✓ Test PASSED");
            test_pass = 1;
        end else begin
            $display("✗ Test FAILED");
            test_pass = 0;
        end
        
        // Finish simulation
        #100;
        $finish;
    end
    
    // ===============================
    // Timeout Watchdog
    // ===============================
    initial begin
        // Set a reasonable timeout (adjust based on your design)
        #(CLK_PERIOD * 100000);
        $display("\n========================================");
        $display("ERROR: TIMEOUT!");
        $display("========================================");
        $display("The design did not complete within the expected time.");
        $display("Current phase: %0s", phase_name);
        $display("Cycle count: %0d", cycle_count);
        $display("========================================\n");
        $finish;
    end
    
    // ===============================
    // Optional: Detailed Module Monitoring
    // ===============================
    // Uncomment to see internal signals
    /*
    always @(posedge clk) begin
        if (dut.edge_valid)
            $display("[%0t] Edge Encoder: edge %0d encoded", $time, dut.edge_addr_out);
        if (dut.node_valid)
            $display("[%0t] Node Encoder: node %0d encoded", $time, dut.node_addr_out);
        if (dut.mp_scatter_sum_we)
            $display("[%0t] Scatter-sum write (in=%0d, out=%0d)", 
                    $time, dut.mp_in_node_index_ss, dut.mp_out_node_index_ss);
        if (dut.dec_data_valid)
            $display("[%0t] Edge Decoder: edge %0d decoded", $time, dut.dec_edge_addr_out);
    end
    */
    
    // ===============================
    // Phase Statistics
    // ===============================
    integer phase_start_time[0:9];
    integer phase_duration[0:9];
    integer i;
    
    initial begin
        for (i = 0; i < 10; i = i + 1) begin
            phase_start_time[i] = 0;
            phase_duration[i] = 0;
        end
    end
    
    always @(posedge clk) begin
        if (current_phase != prev_phase) begin
            // Record end time of previous phase
            if (prev_phase < 10 && phase_start_time[prev_phase] != 0) begin
                phase_duration[prev_phase] = cycle_count - phase_start_time[prev_phase];
            end
            // Record start time of new phase
            if (current_phase < 10) begin
                phase_start_time[current_phase] = cycle_count;
            end
        end
    end
    
    // Print phase statistics at end
    initial begin
        wait(processing_done);
        #(CLK_PERIOD * 10);
        
        $display("\n========================================");
        $display("PHASE STATISTICS (in clock cycles)");
        $display("========================================");
        for (i = 0; i < 10; i = i + 1) begin
            if (phase_duration[i] > 0) begin
                $display("  %-25s : %0d cycles", get_phase_name(i), phase_duration[i]);
            end
        end
        $display("========================================\n");
    end
    
    // ===============================
    // Waveform Dump
    // ===============================
    initial begin
        $dumpfile("tb_top_module.vcd");
        $dumpvars(0, tb_top_module);
        
        // Optionally dump specific internal signals for debugging
        $dumpvars(1, dut.edge_enc);
        $dumpvars(1, dut.node_enc);
        $dumpvars(1, dut.mp_wrapper);
        $dumpvars(1, dut.edge_dec);
    end
    
    // ===============================
    // Helper Function
    // ===============================
    function [255:0] get_phase_name;
        input [3:0] phase;
        begin
            case (phase)
                4'd0: get_phase_name = "IDLE";
                4'd1: get_phase_name = "EDGE_ENCODE";
                4'd2: get_phase_name = "EDGE_ENCODE_WAIT";
                4'd3: get_phase_name = "NODE_ENCODE";
                4'd4: get_phase_name = "NODE_ENCODE_WAIT";
                4'd5: get_phase_name = "MESSAGE_PASSING";
                4'd6: get_phase_name = "MESSAGE_PASSING_WAIT";
                4'd7: get_phase_name = "EDGE_DECODE";
                4'd8: get_phase_name = "EDGE_DECODE_WAIT";
                4'd9: get_phase_name = "DONE";
                default: get_phase_name = "UNKNOWN";
            endcase
        end
    endfunction

endmodule