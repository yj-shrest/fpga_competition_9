// ============================================================
// File: top.v
// Description: Example top module using URAM wrapper
// ============================================================

module top (
    input  wire        clk,
    input  wire        rst,

    // External write interface
    input  wire        wr_en,
    input  wire [11:0] wr_addr,
    input  wire [71:0] wr_data,

    // External read interface
    input  wire        rd_en,
    input  wire [11:0] rd_addr,
    output wire [71:0] rd_data
);

    // --------------------------------------------------------
    // URAM instance
    // --------------------------------------------------------
    uram #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(72)
    ) uram_inst (
        .clk(clk),

        // -------- Port A : WRITE --------
        .en_a(wr_en),
        .we_a(wr_en),
        .addr_a(wr_addr),
        .din_a(wr_data),
        .dout_a(),        // unused

        // -------- Port B : READ --------
        .en_b(rd_en),
        .we_b(1'b0),      // read-only
        .addr_b(rd_addr),
        .din_b(72'd0),
        .dout_b(rd_data)
    );

endmodule
