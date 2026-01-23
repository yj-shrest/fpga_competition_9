`timescale 1ns / 1ps
module tb_bram_init_add1;

    localparam RAM_WIDTH     = 16;
    localparam RAM_ADDR_BITS = 12;
    localparam DEPTH         = 100; // small depth for simulation
    integer i;

    reg clock, reset, start;
    wire done;

    // Instantiate DUT
    bram_init_add1 #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_ADDR_BITS(RAM_ADDR_BITS)
    ) dut (
        .clock(clock),
        .reset(reset),
        .start(start),
        .done(done)
    );

    // Clock generator
    always #5 clock = ~clock;

    initial begin
        clock = 0;
        reset = 1;
        start = 0;

        #20;
        reset = 0;

        // Print INITIAL contents
        $display("\n===== INITIAL BRAM CONTENTS =====");
        for (i=0; i<DEPTH; i=i+1)
            $display("ADDR %0d : %h", i, dut.bram_inst.ram_name[i]);

        // Start FSM
        #20;
        start = 1;
        #10;
        start = 0;

        // Wait for operation to finish
        wait(done);
        #20;

        // Print FINAL contents
        $display("\n===== FINAL BRAM CONTENTS =====");
        for (i=0; i<DEPTH; i=i+1)
            $display("ADDR %0d : %h", i, dut.bram_inst.ram_name[i]);

        $display("\nSimulation completed.\n");
        $finish;
    end

endmodule
