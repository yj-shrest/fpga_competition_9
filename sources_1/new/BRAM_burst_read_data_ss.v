`timescale 1ns / 1ps

module bram_burst_wrapper_ss #(
    parameter RAM_WIDTH       = 8,
    parameter RAM_ADDR_BITS   = 12,
    parameter MAX_BURST_SIZE  = 32,  // Maximum number of words in a burst
    parameter DATA_FILE       = "",
    parameter INIT_START_ADDR = 0,
    parameter INIT_END_ADDR   = 0
)(
    input clock,
    input reset,

    // Burst Write Port (Scatter-Sum)
    input                     write_start,      // Start burst write
    input [RAM_ADDR_BITS-1:0] write_addr_base,  // Starting address for write
    input [$clog2(MAX_BURST_SIZE):0] write_burst_size, // Number of words to write
    input [RAM_WIDTH*MAX_BURST_SIZE-1:0] write_data,   // Concatenated input data
    output reg                write_done,       // Write complete signal
    output reg                write_busy,       // Busy during write operation

    // Burst Read Port
    input                     read_start,       // Start burst read
    input [RAM_ADDR_BITS-1:0] read_addr_base,   // Starting address for read
    input [$clog2(MAX_BURST_SIZE):0] read_burst_size, // Number of words to read
    output reg [RAM_WIDTH*MAX_BURST_SIZE-1:0] read_data, // Concatenated output data
    output reg                read_valid,       // Data valid signal
    output reg                read_busy         // Busy during read operation
);

    // Internal BRAM signals
    reg                      bram_we_a;
    reg                      bram_en_a;
    reg [RAM_ADDR_BITS-1:0]  bram_addr_a;
    reg [RAM_WIDTH-1:0]      bram_din_a;
    
    wire                     bram_en_b;
    wire [RAM_ADDR_BITS-1:0] bram_addr_b;
    wire [RAM_WIDTH-1:0]     bram_dout_b;

    // Write state machine - modified for read-modify-write
    localparam W_IDLE       = 3'b000;
    localparam W_READ_WAIT  = 3'b001;  // Wait for read data
    localparam W_READ_DATA  = 3'b010;  // Capture read data
    localparam W_ADD_WRITE  = 3'b011;  // Add and write back
    localparam W_DONE       = 3'b100;
    
    reg [2:0] write_state;
    reg [$clog2(MAX_BURST_SIZE):0] write_counter;
    reg [$clog2(MAX_BURST_SIZE):0] write_burst_size_reg;
    reg [RAM_ADDR_BITS-1:0] write_current_addr;
    reg [RAM_WIDTH*MAX_BURST_SIZE-1:0] write_data_reg;
    reg [RAM_WIDTH-1:0] old_data;  // Store read data for addition
    
    // Read state machine
    localparam R_IDLE       = 2'b00;
    localparam R_READING    = 2'b01;
    localparam R_WAIT_LAST  = 2'b10;
    localparam R_DONE       = 2'b11;
    
    reg [1:0] read_state;
    reg [$clog2(MAX_BURST_SIZE):0] read_counter;
    reg [$clog2(MAX_BURST_SIZE):0] read_burst_size_reg;
    reg [RAM_ADDR_BITS-1:0] read_current_addr;
    
    // Temporary storage for burst read data
    reg [RAM_WIDTH-1:0] temp_read_data [0:MAX_BURST_SIZE-1];
    integer i;

    // Instantiate the dual-port BRAM
    bram_dual #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_ADDR_BITS(RAM_ADDR_BITS),
        .DATA_FILE(DATA_FILE),
        .INIT_START_ADDR(INIT_START_ADDR),
        .INIT_END_ADDR(INIT_END_ADDR)
    ) bram_inst (
        .clock(clock),
        
        // Port A - Write (controlled by wrapper)
        .we_a(bram_we_a),
        .en_a(bram_en_a),
        .addr_a(bram_addr_a),
        .din_a(bram_din_a),
        
        // Port B - Read (controlled by wrapper)
        .en_b(bram_en_b),
        .addr_b(bram_addr_b),
        .dout_b(bram_dout_b)
    );

    // Control logic for burst reads
    // Read port is used by both read operations and write read-modify-write
    assign bram_en_b = (read_state == R_READING) || (write_state == W_READ_WAIT);
    assign bram_addr_b = (read_state == R_READING) ? read_current_addr : write_current_addr;

    // ========================================
    // WRITE STATE MACHINE (Read-Modify-Write for Scatter-Sum)
    // ========================================
    always @(posedge clock) begin
        if (reset) begin
            write_state <= W_IDLE;
            write_counter <= 0;
            write_done <= 1'b0;
            write_busy <= 1'b0;
            write_current_addr <= 0;
            write_burst_size_reg <= 0;
            write_data_reg <= 0;
            old_data <= 0;
            bram_we_a <= 1'b0;
            bram_en_a <= 1'b0;
            bram_addr_a <= 0;
            bram_din_a <= 0;
        end else begin
            case (write_state)
                W_IDLE: begin
                    write_done <= 1'b0;
                    bram_we_a <= 1'b0;
                    bram_en_a <= 1'b0;
                    
                    if (write_start && write_burst_size > 0 && write_burst_size <= MAX_BURST_SIZE) begin
                        write_state <= W_READ_WAIT;
                        write_busy <= 1'b1;
                        write_current_addr <= write_addr_base;
                        write_counter <= 0;
                        write_burst_size_reg <= write_burst_size;
                        write_data_reg <= write_data;
                    end else begin
                        write_busy <= 1'b0;
                    end
                end
                
                W_READ_WAIT: begin
                    // Initiate read from port B (address already set via bram_addr_b)
                    // Wait one cycle for BRAM read latency
                    write_state <= W_READ_DATA;
                end
                
                W_READ_DATA: begin
                    // Capture the read data from port B
                    old_data <= bram_dout_b;
                    write_state <= W_ADD_WRITE;
                end
                
                W_ADD_WRITE: begin
                    if (write_counter < write_burst_size_reg) begin
                        // Enable write to BRAM on port A
                        bram_en_a <= 1'b1;
                        bram_we_a <= 1'b1;
                        bram_addr_a <= write_current_addr;
                        
                        // Add new data to old data (scatter-sum operation)
                        bram_din_a <= old_data + write_data_reg[write_counter*RAM_WIDTH +: RAM_WIDTH];
                        
                        // Increment for next iteration
                        write_current_addr <= write_current_addr + 1;
                        write_counter <= write_counter + 1;
                        
                        // Check if this is the last write
                        if (write_counter == write_burst_size_reg - 1) begin
                            write_state <= W_DONE;
                        end else begin
                            // Need to read next location
                            write_state <= W_READ_WAIT;
                        end
                    end
                end
                
                W_DONE: begin
                    bram_we_a <= 1'b0;
                    bram_en_a <= 1'b0;
                    write_done <= 1'b1;
                    write_busy <= 1'b0;
                    write_state <= W_IDLE;
                end
                
                default: begin
                    write_state <= W_IDLE;
                end
            endcase
        end
    end

    // ========================================
    // READ STATE MACHINE
    // ========================================
    always @(posedge clock) begin
        if (reset) begin
            read_state <= R_IDLE;
            read_counter <= 0;
            read_valid <= 1'b0;
            read_busy <= 1'b0;
            read_current_addr <= 0;
            read_burst_size_reg <= 0;
            for (i = 0; i < MAX_BURST_SIZE; i = i + 1) begin
                temp_read_data[i] <= 0;
            end
        end else begin
            case (read_state)
                R_IDLE: begin
                    read_valid <= 1'b0;
                    if (read_start && read_burst_size > 0 && read_burst_size <= MAX_BURST_SIZE && !write_busy) begin
                        read_state <= R_READING;
                        read_busy <= 1'b1;
                        read_current_addr <= read_addr_base;
                        read_counter <= 0;
                        read_burst_size_reg <= read_burst_size;
                    end else begin
                        read_busy <= 1'b0;
                    end
                end
                
                R_READING: begin
                    if (read_counter < read_burst_size_reg) begin
                        read_current_addr <= read_current_addr + 1;
                        read_counter <= read_counter + 1;
                        
                        // Store previous cycle's data (BRAM has 1 cycle latency)
                        if (read_counter > 0) begin
                            temp_read_data[read_counter - 1] <= bram_dout_b;
                        end
                        
                        // Check if this is the last read request
                        if (read_counter == read_burst_size_reg - 1) begin
                            read_state <= R_WAIT_LAST;
                        end
                    end
                end
                
                R_WAIT_LAST: begin
                    // Wait one more cycle for the last data to arrive
                    temp_read_data[read_burst_size_reg - 1] <= bram_dout_b;
                    read_state <= R_DONE;
                end
                
                R_DONE: begin
                    // Concatenate all data into output register
                    for (i = 0; i < MAX_BURST_SIZE; i = i + 1) begin
                        read_data[i*RAM_WIDTH +: RAM_WIDTH] <= temp_read_data[i];
                    end
                    read_valid <= 1'b1;
                    read_busy <= 1'b0;
                    read_state <= R_IDLE;
                end
            endcase
        end
    end

endmodule