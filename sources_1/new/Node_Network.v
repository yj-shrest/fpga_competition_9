`timescale 1ns / 1ps

//==============================================================================
// Node_Network_Pipelined  —  drop-in replacement for Node_Network
//
// Rewritten to match the working Edge_Network architecture exactly:
//   - CS_IDLE → CS_L1W directly (no CS_L1_WAIT)
//   - concat_latch from concat_fifo[fifo_rptr] before rptr advances
//   - No fifo_rptr_popped mechanism
//   - node_index = idx_load (raw counter, not multiplied)
//   - do_pop gated by st_state == ST_IDLE to prevent store_node_addr clobber
//==============================================================================

module Node_Network #(
    parameter BLOCK_NUM              = 0,
    parameter DATA_BITS              = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter NODE_FEATURES          = 32,
    parameter MAX_NODES              = 0
) (
    input  clk,
    input  rstn,
    input  start,

    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_in,
    output reg                            scatter_sum_features_in_re,
    input                                 scatter_sum_features_in_valid,

    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_out,
    output reg                            scatter_sum_features_out_re,
    input                                 scatter_sum_features_out_valid,

    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg                            current_node_features_re,
    input                                 current_node_features_valid,
    output reg                            current_node_features_we,
    input                                 current_node_features_write_done,

    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg                            initial_node_features_re,
    input                                 initial_node_features_valid,

    output [RAM_ADDR_BITS_FOR_NODE-1:0]  node_address,
    output [RAM_ADDR_BITS_FOR_NODE-6:0]  node_index,

    output [DATA_BITS*NODE_FEATURES-1:0] node_output,
    output reg                            done
);

    // =========================================================================
    // Load FSM states
    // =========================================================================
    localparam LS_IDLE   = 3'd0,
               LS_LOAD1  = 3'd1,
               LS_CONCAT = 3'd2,
               LS_DRAIN  = 3'd3;

    reg [2:0] ls_state;

    // Load-side node index
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] idx_load;

    // Holding registers for the node being loaded
    reg [DATA_BITS*NODE_FEATURES-1:0] load_ss_in, load_ss_out;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_curr,  load_init;

    reg load_rd_done;

    reg [RAM_ADDR_BITS_FOR_NODE-1:0] nodes_dispatched;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] nodes_completed;

    reg layer1_start;   // one-cycle pulse: kicks FIFO push + compute FSM
    reg ec_reset;       // one-cycle pulse: resets nodes_completed

    reg layer1_held, layer2_held, layer3_held;
    reg layer2_start, layer3_start;

    // =========================================================================
    // MLP layer wires
    // =========================================================================
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer1_out;
    wire                                Layer1_out_valid;
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer2_out;
    wire                                Layer2_out_valid;
    wire [NODE_FEATURES*DATA_BITS-1:0] Layer3_out;
    wire                                Layer3_out_valid;

    reg [DATA_BITS*NODE_FEATURES-1:0] Layer1_out_r;
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer2_out_r;
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer3_out_r;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            Layer1_out_r <= 0; Layer2_out_r <= 0; Layer3_out_r <= 0;
        end else begin
            if (Layer1_out_valid) Layer1_out_r <= Layer1_out;
            if (Layer2_out_valid) Layer2_out_r <= Layer2_out;
            if (Layer3_out_valid) Layer3_out_r <= Layer3_out;
        end
    end

    assign node_output = Layer3_out_r;

    // =========================================================================
    // Compute FSM  (matches working Edge_Network exactly)
    //
    // KEY: No CS_L1_WAIT state. CS_IDLE → CS_L1W directly with layer1_held
    // asserted in the same cycle. concat_latch is loaded from concat_fifo
    // [fifo_rptr] on the same posedge (before rptr advances), guaranteeing
    // data is stable one full clock before L1's counter starts ticking.
    // =========================================================================
    localparam CS_IDLE    = 3'd0,
               CS_L1W     = 3'd1,
               CS_L1_GAP  = 3'd2,
               CS_L2W     = 3'd3,
               CS_L2_GAP  = 3'd4,
               CS_L3W     = 3'd5;

    reg [2:0] cs_state;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cs_state <= CS_IDLE;
            layer1_held <= 0; layer2_held <= 0; layer3_held <= 0;
            layer2_start <= 0; layer3_start <= 0;
        end else begin
            layer2_start <= 0;
            layer3_start <= 0;

            case (cs_state)
                CS_IDLE: begin
                    layer1_held <= 0;
                    if (!fifo_empty && (nodes_completed < MAX_NODES)) begin
                        layer1_held <= 1;       // assert IMMEDIATELY
                        cs_state    <= CS_L1W;  // go directly to L1 wait
                    end
                end

                CS_L1W: begin
                    layer1_held <= 1;
                    if (Layer1_out_valid) begin
                        layer1_held  <= 0;
                        layer2_start <= 1;
                        cs_state     <= CS_L1_GAP;
                    end
                end

                CS_L1_GAP: begin
                    layer1_held <= 0;
                    layer2_held <= 1;
                    cs_state    <= CS_L2W;
                end

                CS_L2W: begin
                    layer2_held <= 1;
                    if (Layer2_out_valid) begin
                        layer2_held  <= 0;
                        layer3_start <= 1;
                        cs_state     <= CS_L2_GAP;
                    end
                end

                CS_L2_GAP: begin
                    layer2_held <= 0;
                    layer3_held <= 1;
                    cs_state    <= CS_L3W;
                end

                CS_L3W: begin
                    layer3_held <= (nodes_completed < MAX_NODES) ? 1 : 0;
                    if (Layer3_out_valid) begin
                        layer3_held <= 0;
                        cs_state    <= CS_IDLE;
                    end
                end

                default: cs_state <= CS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Metadata + Concat FIFO  (matches working Edge_Network exactly)
    // =========================================================================
    localparam FIFO_DEPTH = 5;
    localparam FIFO_AW    = 3;

    reg [RAM_ADDR_BITS_FOR_NODE-1:0]    fifo_node_addr [0:FIFO_DEPTH-1];
    reg [4*NODE_FEATURES*DATA_BITS-1:0] concat_fifo    [0:FIFO_DEPTH-1];

    reg [FIFO_AW-1:0] fifo_wptr;
    reg [FIFO_AW-1:0] fifo_rptr;
    reg [FIFO_AW:0]   fifo_count;

    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    wire do_push = layer1_start & ~fifo_full;

    // FIX: gate do_pop with st_state == ST_IDLE to prevent store_node_addr
    // from being clobbered while the store FSM is still writing back the
    // previous node's result. Without this gate, do_pop fires on the same
    // cycle the store FSM enters ST_STORE, overwriting store_node_addr with
    // the NEXT node's address before the current write-back uses it.
    wire do_pop  = (cs_state == CS_IDLE) & ~fifo_empty
                 & (nodes_completed < MAX_NODES)
                 & (st_state == ST_IDLE);

    // Store-side metadata (written by do_pop, read by store FSM + address mux)
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] store_node_addr;

    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wptr <= 0; fifo_rptr <= 0; fifo_count <= 0;
            store_node_addr <= 0;
            for (k = 0; k < FIFO_DEPTH; k = k + 1) begin
                fifo_node_addr[k] <= 0;
                concat_fifo[k]    <= 0;
            end
        end else begin
            if (do_push) begin
                fifo_node_addr[fifo_wptr] <= idx_load * NODE_FEATURES;
                concat_fifo[fifo_wptr]    <= {load_ss_in, load_ss_out,
                                               load_curr,  load_init};
                fifo_wptr <= (fifo_wptr == FIFO_DEPTH-1) ? 0 : fifo_wptr + 1;
            end
            if (do_pop) begin
                store_node_addr <= fifo_node_addr[fifo_rptr];
                fifo_rptr <= (fifo_rptr == FIFO_DEPTH-1) ? 0 : fifo_rptr + 1;
            end
            case ({do_push, do_pop})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: ;
            endcase
        end
    end

    // =========================================================================
    // concat_latch  (matches working Edge_Network exactly)
    //
    // Loaded on the SAME posedge as do_pop, reading concat_fifo[fifo_rptr]
    // BEFORE fifo_rptr advances (Verilog NBA semantics: RHS evaluates with
    // pre-update values). This guarantees concat_latch is stable one full
    // clock cycle before layer1_held goes HIGH and L1 starts counting.
    //
    // The broken version used a CS_L1_WAIT state + fifo_rptr_popped, which
    // delayed concat_latch by one cycle — it was written on the SAME posedge
    // that layer1_held went HIGH, creating a data setup timing hazard.
    // =========================================================================
    reg [4*NODE_FEATURES*DATA_BITS-1:0] concat_latch;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            concat_latch <= 0;
        else if (cs_state == CS_IDLE && !fifo_empty && (nodes_completed < MAX_NODES)
                 && (st_state == ST_IDLE))
            concat_latch <= concat_fifo[fifo_rptr];
    end

    // =========================================================================
    // Store FSM
    // =========================================================================
    localparam ST_IDLE  = 2'd0,
               ST_STORE = 2'd1;

    reg [1:0] st_state;
    reg store_initiated;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            st_state        <= ST_IDLE;
            store_initiated <= 0;
            nodes_completed <= 0;
            current_node_features_we <= 0;
        end else begin
            if (ec_reset) begin
                nodes_completed <= 0;
                st_state        <= ST_IDLE;
                store_initiated <= 0;
            end
            current_node_features_we <= 0;

            case (st_state)
                ST_IDLE: begin
                    store_initiated <= 0;
                    if (Layer3_out_valid && (nodes_completed < MAX_NODES)) begin
                        st_state <= ST_STORE;
                    end
                end

                ST_STORE: begin
                    if (!store_initiated) begin
                        current_node_features_we <= 1;
                        store_initiated          <= 1;
                    end
                    if (current_node_features_write_done) begin
                        if (nodes_completed < MAX_NODES)
                            nodes_completed <= nodes_completed + 1;
                        store_initiated <= 0;
                        st_state        <= ST_IDLE;
                    end
                end

                default: st_state <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Load FSM
    // =========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ls_state          <= LS_IDLE;
            idx_load          <= 0;
            nodes_dispatched  <= 0;
            layer1_start      <= 0;
            ec_reset          <= 0;
            load_rd_done      <= 0;
            load_ss_in        <= 0;  load_ss_out <= 0;
            load_curr         <= 0;  load_init   <= 0;
            scatter_sum_features_in_re  <= 0;
            scatter_sum_features_out_re <= 0;
            current_node_features_re    <= 0;
            initial_node_features_re    <= 0;
            done                        <= 0;
        end else begin
            layer1_start              <= 0;
            ec_reset                  <= 0;
            scatter_sum_features_in_re  <= 0;
            scatter_sum_features_out_re <= 0;
            current_node_features_re    <= 0;
            initial_node_features_re    <= 0;
            done                        <= 0;

            case (ls_state)
                LS_IDLE: begin
                    if (start) begin
                        idx_load         <= 0;
                        nodes_dispatched <= 0;
                        load_rd_done     <= 0;
                        ec_reset         <= 1;
                        ls_state         <= LS_LOAD1;
                    end
                end

                LS_LOAD1: begin
                    if (!load_rd_done) begin
                        scatter_sum_features_in_re  <= 1;
                        scatter_sum_features_out_re <= 1;
                        current_node_features_re    <= 1;
                        initial_node_features_re    <= 1;
                        load_rd_done                <= 1;
                    end
                    if (scatter_sum_features_in_valid  &&
                        scatter_sum_features_out_valid &&
                        current_node_features_valid    &&
                        initial_node_features_valid) begin
                        load_ss_in   <= scatter_sum_features_in;
                        load_ss_out  <= scatter_sum_features_out;
                        load_curr    <= current_node_features;
                        load_init    <= initial_node_features;
                        load_rd_done <= 0;
                        ls_state     <= LS_CONCAT;
                    end
                end

                LS_CONCAT: begin
                    layer1_start     <= 1;
                    nodes_dispatched <= nodes_dispatched + 1;

                    if (idx_load < MAX_NODES - 1)
                        idx_load <= idx_load + 1;

                    if (nodes_dispatched + 1 < MAX_NODES) begin
                        load_rd_done <= 0;
                        ls_state     <= LS_LOAD1;
                    end else begin
                        ls_state <= LS_DRAIN;
                    end
                end

                LS_DRAIN: begin
                    if (nodes_completed >= MAX_NODES) begin
                        done <= 1;
                    end
                end

                default: ls_state <= LS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Address outputs
    //
    // FIX: node_index = idx_load (raw counter, NOT multiplied by NODE_FEATURES).
    // The original had: node_index = idx_load * NODE_FEATURES, which after
    // Verilog truncation to [RAM_ADDR_BITS_FOR_NODE-6:0] always produced 0
    // (the lower 5 bits of any value << 5 are zero).
    //
    // node_address is the full byte address — muxed for store phase.
    // node_index is the raw node counter — used by parent for ROM indexing.
    // =========================================================================
    assign node_address = (st_state == ST_STORE) ? store_node_addr
                                                 : idx_load * NODE_FEATURES;
    assign node_index   = idx_load;

    // =========================================================================
    // MLP Layer instantiation
    // .rstn connected to module rstn (NOT to layer start signal)
    // .start connected to held signals (NOT one-cycle pulses)
    // =========================================================================
    generate
        case (BLOCK_NUM)
        0: begin : block_0_layers
            MP_Node_Layer_B0_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B0_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B0_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        1: begin : block_1_layers
            MP_Node_Layer_B1_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B1_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B1_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        2: begin : block_2_layers
            MP_Node_Layer_B2_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B2_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B2_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        3: begin : block_3_layers
            MP_Node_Layer_B3_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B3_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B3_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        4: begin : block_4_layers
            MP_Node_Layer_B4_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B4_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B4_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        5: begin : block_5_layers
            MP_Node_Layer_B5_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B5_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B5_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        6: begin : block_6_layers
            MP_Node_Layer_B6_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B6_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B6_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        7: begin : block_7_layers
            MP_Node_Layer_B7_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Node_Layer_B7_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Node_Layer_B7_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        default: begin : block_default
            initial begin $finish; end
        end
        endcase
    endgenerate

endmodule