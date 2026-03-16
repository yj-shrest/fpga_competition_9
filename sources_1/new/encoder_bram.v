`timescale 1ns / 1ps

// encoder_bram – single-port synchronous BRAM for storing encoder output features.
//
// Supports sequential burst writes (from the encoder) and sequential burst reads
// (from the message-passing stage) using simple valid/ready handshaking.
//
// Write side: raise write_start for one cycle together with write_addr_base,
//   write_data, and write_burst_size.  The module writes one word per clock
//   cycle until all write_burst_size words have been stored, then pulses
//   write_done for one cycle.
//
// Read side: raise read_start for one cycle together with read_addr_base and
//   read_burst_size.  One clock after all words have been read the module
//   presents them on read_data and asserts read_valid for one cycle.

module encoder_bram #(
    parameter DATA_BITS       = 8,           // Width of each data word
    parameter ADDR_BITS       = 14,          // Address width
    parameter MAX_BURST_SIZE  = 32,          // Maximum burst length
    parameter DATA_FILE       = "",          // Optional initialisation file
    parameter INIT_START_ADDR = 0,
    parameter INIT_END_ADDR   = 0
)(
    input  wire                                clock,
    input  wire                                reset,

    // ---- Write port ----
    input  wire                                write_start,
    input  wire [ADDR_BITS-1:0]                write_addr_base,
    input  wire [$clog2(MAX_BURST_SIZE):0]     write_burst_size,
    input  wire [DATA_BITS*MAX_BURST_SIZE-1:0] write_data,
    output reg                                 write_done,
    output reg                                 write_busy,

    // ---- Read port ----
    input  wire                                read_start,
    input  wire [ADDR_BITS-1:0]                read_addr_base,
    input  wire [$clog2(MAX_BURST_SIZE):0]     read_burst_size,
    output reg  [DATA_BITS*MAX_BURST_SIZE-1:0] read_data,
    output reg                                 read_valid,
    output reg                                 read_busy
);

    // -----------------------------------------------------------------------
    // Underlying memory array (infers block RAM on FPGA targets)
    // -----------------------------------------------------------------------
    reg [DATA_BITS-1:0] mem [0:(2**ADDR_BITS)-1];

    initial begin
        if (DATA_FILE != "")
            $readmemb(DATA_FILE, mem, INIT_START_ADDR, INIT_END_ADDR);
    end

    // -----------------------------------------------------------------------
    // Write state machine
    // -----------------------------------------------------------------------
    localparam W_IDLE    = 2'd0;
    localparam W_WRITING = 2'd1;
    localparam W_DONE    = 2'd2;

    reg [1:0]                          write_state;
    reg [$clog2(MAX_BURST_SIZE):0]     write_counter;
    reg [$clog2(MAX_BURST_SIZE):0]     write_burst_size_reg;
    reg [ADDR_BITS-1:0]                write_current_addr;
    reg [DATA_BITS*MAX_BURST_SIZE-1:0] write_data_reg;

    always @(posedge clock) begin
        if (reset) begin
            write_state   <= W_IDLE;
            write_done    <= 1'b0;
            write_busy    <= 1'b0;
            write_counter <= 0;
        end else begin
            case (write_state)
                W_IDLE: begin
                    write_done <= 1'b0;
                    if (write_start) begin
                        write_burst_size_reg <= write_burst_size;
                        write_current_addr   <= write_addr_base;
                        write_data_reg       <= write_data;
                        write_counter        <= 0;
                        write_busy           <= 1'b1;
                        write_state          <= W_WRITING;
                    end
                end

                W_WRITING: begin
                    // Write one word per cycle
                    mem[write_current_addr] <= write_data_reg[write_counter * DATA_BITS +: DATA_BITS];
                    write_current_addr      <= write_current_addr + 1;
                    if (write_counter == write_burst_size_reg - 1) begin
                        write_state <= W_DONE;
                    end else begin
                        write_counter <= write_counter + 1;
                    end
                end

                W_DONE: begin
                    write_done  <= 1'b1;
                    write_busy  <= 1'b0;
                    write_state <= W_IDLE;
                end

                default: write_state <= W_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read state machine
    // -----------------------------------------------------------------------
    localparam R_IDLE    = 2'd0;
    localparam R_READING = 2'd1;
    localparam R_DONE    = 2'd2;

    reg [1:0]                      read_state;
    reg [$clog2(MAX_BURST_SIZE):0] read_counter;
    reg [$clog2(MAX_BURST_SIZE):0] read_burst_size_reg;
    reg [ADDR_BITS-1:0]            read_current_addr;
    integer ri;

    initial begin
        read_data = {(DATA_BITS*MAX_BURST_SIZE){1'b0}};
    end

    always @(posedge clock) begin
        if (reset) begin
            read_state   <= R_IDLE;
            read_valid   <= 1'b0;
            read_busy    <= 1'b0;
            read_counter <= 0;
        end else begin
            case (read_state)
                R_IDLE: begin
                    read_valid <= 1'b0;
                    if (read_start) begin
                        read_burst_size_reg <= read_burst_size;
                        read_current_addr   <= read_addr_base;
                        read_counter        <= 0;
                        read_busy           <= 1'b1;
                        read_state          <= R_READING;
                    end
                end

                R_READING: begin
                    // Read directly from the memory array (no pipeline latency
                    // since this is a register-file model, not a true BRAM port)
                    read_data[read_counter * DATA_BITS +: DATA_BITS] <= mem[read_current_addr];
                    read_current_addr <= read_current_addr + 1;
                    if (read_counter == read_burst_size_reg - 1) begin
                        read_state <= R_DONE;
                    end else begin
                        read_counter <= read_counter + 1;
                    end
                end

                R_DONE: begin
                    read_valid <= 1'b1;
                    read_busy  <= 1'b0;
                    read_state <= R_IDLE;
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

endmodule
