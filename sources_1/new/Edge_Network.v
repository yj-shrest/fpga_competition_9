`timescale 1ns / 1ps

//==============================================================================
// Edge_Network_Pipelined  —  drop-in replacement for Edge_Network
//==============================================================================

module Edge_Network #(
    parameter BLOCK_NUM              = 0,
    parameter DATA_BITS              = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter RAM_ADDR_BITS_FOR_EDGE = 0,
    parameter NODE_FEATURES          = 32,
    parameter EDGE_FEATURES          = 32,
    parameter MAX_EDGES              = 0
) (
    input  clk,
    input  rstn,
    input  start,

    input  [DATA_BITS*EDGE_FEATURES-1:0] initial_edge_features,
    output reg                            initial_edge_features_re,
    input                                 initial_edge_features_valid,

    input  [DATA_BITS*EDGE_FEATURES-1:0] current_edge_features,
    output reg                            current_edge_features_re,
    input                                 current_edge_features_valid,
    output reg                            current_edge_features_we,
    input                                 current_edge_features_write_done,

    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg                            initial_node_features_re,
    input                                 initial_node_features_valid,

    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg                            current_node_features_re,
    input                                 current_node_features_valid,

    input  [RAM_ADDR_BITS_FOR_NODE-1:0]  source_node_index,
    output reg                            source_node_index_re,
    input                                 source_node_index_valid,

    input  [RAM_ADDR_BITS_FOR_NODE-1:0]  destination_node_index,
    output reg                            destination_node_index_re,
    input                                 destination_node_index_valid,

    output [RAM_ADDR_BITS_FOR_EDGE-1:0]  edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-6:0]  edge_index,

    output [RAM_ADDR_BITS_FOR_NODE-1:0]  in_node_index_ss,
    input                                 in_node_ss_write_done,
    output [RAM_ADDR_BITS_FOR_NODE-1:0]  out_node_index_ss,
    output reg                            scatter_sum_we,
    input                                 out_node_ss_write_done,

    output reg [RAM_ADDR_BITS_FOR_NODE-1:0] node_index,

    output reg [DATA_BITS*EDGE_FEATURES-1:0] edge_output,
    output reg                                done
);

    localparam LS_IDLE   = 3'd0,
               LS_LOAD1  = 3'd1,
               LS_LOAD2  = 3'd2,
               LS_LOAD3  = 3'd3,
               LS_CONCAT = 3'd4,
               LS_DRAIN  = 3'd5;

    reg [2:0] ls_state;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] idx_load;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] load_src, load_dest;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_init_src, load_curr_src;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_init_dest, load_curr_dest;
    reg [DATA_BITS*EDGE_FEATURES-1:0] load_init_edge, load_curr_edge;
    reg load_rd1_done, load_rd2_done, load_rd3_done;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] edges_dispatched;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] edges_completed;
    reg layer1_start;
    reg ec_reset;
    reg layer1_held, layer2_held, layer3_held;

    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer1_out;
    wire                                Layer1_out_valid;
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer2_out;
    wire                                Layer2_out_valid;
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer3_out;
    wire                                Layer3_out_valid;

    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer1_out_r;
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer2_out_r;
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer3_out_r;

    reg layer2_start, layer3_start;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            Layer1_out_r <= 0; Layer2_out_r <= 0; Layer3_out_r <= 0;
        end else begin
            if (Layer1_out_valid) Layer1_out_r <= Layer1_out;
            if (Layer2_out_valid) Layer2_out_r <= Layer2_out;
            if (Layer3_out_valid) Layer3_out_r <= Layer3_out;
        end
    end

    // =========================================================================
    // Compute FSM
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
                    if (!fifo_empty && (edges_completed < MAX_EDGES)) begin
                        layer1_held <= 1;
                        cs_state    <= CS_L1W;
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
                    layer3_held <= (edges_completed < MAX_EDGES) ? 1 : 0;
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
    // Metadata + Concat FIFO
    // =========================================================================
    localparam FIFO_DEPTH = 5;
    localparam FIFO_AW    = 3;

    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] fifo_edge_addr [0:FIFO_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] fifo_src        [0:FIFO_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] fifo_dest       [0:FIFO_DEPTH-1];
    reg [6*EDGE_FEATURES*DATA_BITS-1:0] concat_fifo  [0:FIFO_DEPTH-1];

    reg [FIFO_AW-1:0] fifo_wptr;
    reg [FIFO_AW-1:0] fifo_rptr;
    reg [FIFO_AW:0]   fifo_count;

    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    wire do_push = layer1_start & ~fifo_full;
    wire do_pop  = (cs_state == CS_IDLE) & ~fifo_empty & (edges_completed < MAX_EDGES);

    // Store-side metadata (written here, read by store FSM)
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] store_edge_addr;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] store_src_r, store_dest_r;

    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wptr <= 0; fifo_rptr <= 0; fifo_count <= 0;
            store_edge_addr <= 0; store_src_r <= 0; store_dest_r <= 0;
            for (k = 0; k < FIFO_DEPTH; k = k + 1) begin
                fifo_edge_addr[k] <= 0;
                fifo_src[k]       <= 0;
                fifo_dest[k]      <= 0;
                concat_fifo[k]    <= 0;
            end
        end else begin
            if (do_push) begin
                fifo_edge_addr[fifo_wptr] <= idx_load * EDGE_FEATURES;
                fifo_src[fifo_wptr]       <= load_src;
                fifo_dest[fifo_wptr]      <= load_dest;
                concat_fifo[fifo_wptr]    <= {load_curr_edge, load_init_edge,
                                               load_curr_src,  load_init_src,
                                               load_curr_dest, load_init_dest};
                fifo_wptr <= (fifo_wptr == FIFO_DEPTH-1) ? 0 : fifo_wptr + 1;
            end
            if (do_pop) begin
                store_edge_addr <= fifo_edge_addr[fifo_rptr];
                store_src_r     <= fifo_src[fifo_rptr];
                store_dest_r    <= fifo_dest[fifo_rptr];
                fifo_rptr <= (fifo_rptr == FIFO_DEPTH-1) ? 0 : fifo_rptr + 1;
            end
            case ({do_push, do_pop})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: ;
            endcase
        end
    end

    // Latch concat data when compute FSM picks up edge — stable for full L1 compute
    reg [6*EDGE_FEATURES*DATA_BITS-1:0] concat_latch;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            concat_latch <= 0;
        else if (cs_state == CS_IDLE && !fifo_empty && (edges_completed < MAX_EDGES))
            concat_latch <= concat_fifo[fifo_rptr];
    end

    // =========================================================================
    // Store FSM
    // =========================================================================
    localparam ST_IDLE  = 2'd0,
               ST_STORE = 2'd1;

    reg [1:0] st_state;
    reg store_writes_initiated;
    reg curr_wr_cap, ss_in_cap, ss_out_cap;

    wire all_writes_done = store_writes_initiated & curr_wr_cap & ss_in_cap & ss_out_cap;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            curr_wr_cap <= 0; ss_in_cap <= 0; ss_out_cap <= 0;
        end else if (!store_writes_initiated) begin
            curr_wr_cap <= 0; ss_in_cap <= 0; ss_out_cap <= 0;
        end else begin
            if (current_edge_features_write_done) curr_wr_cap <= 1;
            if (in_node_ss_write_done)             ss_in_cap  <= 1;
            if (out_node_ss_write_done)            ss_out_cap <= 1;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            st_state               <= ST_IDLE;
            store_writes_initiated <= 0;
            edges_completed        <= 0;
            edge_output            <= 0;
            current_edge_features_we <= 0;
            scatter_sum_we           <= 0;
        end else begin
            if (ec_reset) begin
                edges_completed        <= 0;
                st_state               <= ST_IDLE;
                store_writes_initiated <= 0;
            end
            current_edge_features_we <= 0;
            scatter_sum_we           <= 0;

            case (st_state)
                ST_IDLE: begin
                    store_writes_initiated <= 0;
                    if (Layer3_out_valid && (edges_completed < MAX_EDGES)) begin
                        edge_output <= Layer3_out;
                        st_state    <= ST_STORE;
                    end
                end

                ST_STORE: begin
                    if (!store_writes_initiated) begin
                        current_edge_features_we <= 1;
                        scatter_sum_we           <= 1;
                        store_writes_initiated   <= 1;
                    end
                    if (all_writes_done) begin
                        if (edges_completed < MAX_EDGES)
                            edges_completed <= edges_completed + 1;
                        store_writes_initiated <= 0;
                        st_state               <= ST_IDLE;
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
            ls_state         <= LS_IDLE;
            idx_load         <= 0;
            edges_dispatched <= 0;
            layer1_start     <= 0;
            ec_reset         <= 0;
            load_rd1_done    <= 0;
            load_rd2_done    <= 0;
            load_rd3_done    <= 0;
            load_src         <= 0;  load_dest      <= 0;
            load_init_src    <= 0;  load_curr_src  <= 0;
            load_init_dest   <= 0;  load_curr_dest <= 0;
            load_init_edge   <= 0;  load_curr_edge <= 0;
            initial_edge_features_re  <= 0;
            current_edge_features_re  <= 0;
            initial_node_features_re  <= 0;
            current_node_features_re  <= 0;
            source_node_index_re      <= 0;
            destination_node_index_re <= 0;
            node_index                <= 0;
            done                      <= 0;
        end else begin
            layer1_start              <= 0;
            ec_reset                  <= 0;
            initial_edge_features_re  <= 0;
            current_edge_features_re  <= 0;
            initial_node_features_re  <= 0;
            current_node_features_re  <= 0;
            source_node_index_re      <= 0;
            destination_node_index_re <= 0;
            done                      <= 0;

            case (ls_state)
                LS_IDLE: begin
                    if (start) begin
                        idx_load         <= 0;
                        edges_dispatched <= 0;
                        load_rd1_done    <= 0;
                        load_rd2_done    <= 0;
                        load_rd3_done    <= 0;
                        ec_reset         <= 1;
                        ls_state         <= LS_LOAD1;
                    end
                end

                LS_LOAD1: begin
                    if (!load_rd1_done) begin
                        initial_edge_features_re  <= 1;
                        current_edge_features_re  <= 1;
                        source_node_index_re      <= 1;
                        destination_node_index_re <= 1;
                        load_rd1_done             <= 1;
                    end
                    if (initial_edge_features_valid  &&
                        current_edge_features_valid  &&
                        source_node_index_valid      &&
                        destination_node_index_valid) begin
                        load_init_edge <= initial_edge_features;
                        load_curr_edge <= current_edge_features;
                        load_src       <= source_node_index;
                        load_dest      <= destination_node_index;
                        load_rd1_done  <= 0;
                        ls_state       <= LS_LOAD2;
                    end
                end

                LS_LOAD2: begin
                    if (!load_rd2_done) begin
                        node_index               <= load_src * NODE_FEATURES;
                        initial_node_features_re <= 1;
                        current_node_features_re <= 1;
                        load_rd2_done            <= 1;
                    end
                    if (initial_node_features_valid && current_node_features_valid) begin
                        load_init_src  <= initial_node_features;
                        load_curr_src  <= current_node_features;
                        load_rd2_done  <= 0;
                        ls_state       <= LS_LOAD3;
                    end
                end

                LS_LOAD3: begin
                    if (!load_rd3_done) begin
                        node_index               <= load_dest * NODE_FEATURES;
                        initial_node_features_re <= 1;
                        current_node_features_re <= 1;
                        load_rd3_done            <= 1;
                    end
                    if (initial_node_features_valid && current_node_features_valid) begin
                        load_init_dest <= initial_node_features;
                        load_curr_dest <= current_node_features;
                        load_rd3_done  <= 0;
                        ls_state       <= LS_CONCAT;
                    end
                end

                LS_CONCAT: begin
                    layer1_start     <= 1;
                    edges_dispatched <= edges_dispatched + 1;

                    if (idx_load < MAX_EDGES - 1)
                        idx_load <= idx_load + 1;

                    if (edges_dispatched + 1 < MAX_EDGES) begin
                        load_rd1_done <= 0;
                        load_rd2_done <= 0;
                        load_rd3_done <= 0;
                        ls_state      <= LS_LOAD1;
                    end else begin
                        ls_state <= LS_DRAIN;
                    end
                end

                LS_DRAIN: begin
                    if (edges_completed >= MAX_EDGES) begin
                        done <= 1;
                        // Stay in LS_DRAIN until next start
                    end
                end

                default: ls_state <= LS_IDLE;
            endcase
        end
    end

    assign edge_index   = idx_load;
    assign edge_address = idx_load * EDGE_FEATURES;
    assign out_node_index_ss = store_src_r  * NODE_FEATURES;
    assign in_node_index_ss  = store_dest_r * NODE_FEATURES;

    // =========================================================================
    // MLP Layer instantiation
    // =========================================================================
    generate
        case (BLOCK_NUM)
        0: begin : block_0_layers
            MP_Edge_Layer_B0_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B0_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.done(Layer2_out_valid));
            MP_Edge_Layer_B0_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        1: begin : block_1_layers
            MP_Edge_Layer_B1_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B1_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B1_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        2: begin : block_2_layers
            MP_Edge_Layer_B2_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B2_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B2_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        3: begin : block_3_layers
            MP_Edge_Layer_B3_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B3_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B3_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        4: begin : block_4_layers
            MP_Edge_Layer_B4_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B4_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B4_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        5: begin : block_5_layers
            MP_Edge_Layer_B5_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B5_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B5_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        6: begin : block_6_layers
            MP_Edge_Layer_B6_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B6_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B6_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l3 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer3_held),.data_in_flat(Layer2_out_r),
                .data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
        end
        7: begin : block_7_layers
            MP_Edge_Layer_B7_L1 #(.LAYER_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l1 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer1_held),.data_in_flat(concat_latch),
                .data_out_flat(Layer1_out),.valid_out(Layer1_out_valid));
            MP_Edge_Layer_B7_L2 #(.LAYER_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),
                .DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8)) l2 (
                .clk(clk),.rstn(rstn),.activation_function(1'b1),
                .start(layer2_held),.data_in_flat(Layer1_out_r),
                .data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
            MP_Edge_Layer_B7_L3 #(.LAYER_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),
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