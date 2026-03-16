`timescale 1ns / 1ps

// True dual-port BRAM with independent read and write ports.
// Port A is used for synchronous writes.
// Port B is used for synchronous reads with one-cycle latency.
// Optional initialization from a memory file.

module bram_dual #(
    parameter RAM_WIDTH       = 8,   // Data width in bits
    parameter RAM_ADDR_BITS   = 12,  // Address width (depth = 2^RAM_ADDR_BITS)
    parameter DATA_FILE       = "",  // Optional initialization file (hex/bin)
    parameter INIT_START_ADDR = 0,   // First address to initialize
    parameter INIT_END_ADDR   = 0    // Last  address to initialize
)(
    input                       clock,

    // Port A – write
    input                       we_a,
    input                       en_a,
    input  [RAM_ADDR_BITS-1:0]  addr_a,
    input  [RAM_WIDTH-1:0]      din_a,

    // Port B – read (1-cycle latency)
    input                       en_b,
    input  [RAM_ADDR_BITS-1:0]  addr_b,
    output reg [RAM_WIDTH-1:0]  dout_b
);

    // Underlying memory array
    reg [RAM_WIDTH-1:0] mem [0:(2**RAM_ADDR_BITS)-1];

    // Optional file-based initialization
    initial begin
        if (DATA_FILE != "") begin
            $readmemb(DATA_FILE, mem, INIT_START_ADDR, INIT_END_ADDR);
        end
    end

    // Port A – synchronous write
    always @(posedge clock) begin
        if (en_a && we_a)
            mem[addr_a] <= din_a;
    end

    // Port B – synchronous read (registered output, 1-cycle latency)
    always @(posedge clock) begin
        if (en_b)
            dout_b <= mem[addr_b];
    end

endmodule
