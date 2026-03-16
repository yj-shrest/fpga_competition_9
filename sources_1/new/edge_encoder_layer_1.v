`timescale 1ns / 1ps

module edge_encoder_layer_1 #(
    parameter LAYER_NO       = 1,
    parameter NUM_NEURONS    = 32,
    parameter NUM_FEATURES   = 6,
    parameter DATA_BITS      = 8,       // input/output data width
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8,
    // Layer norm parameters
    parameter LN_DATA_BITS      = 24,   // layer norm internal width Q14.10
    parameter LN_DATA_FRAC_BITS = 10,
    parameter LN_SCALE_BITS     = 8,
    parameter LN_FRAC_BITS      = 6,
    parameter LN_INV_SQRT_BITS  = 16,
    parameter LN_INV_SQRT_FRAC  = 11,
    parameter LN_VAR_BITS       = 45,
    parameter LN_LUT_BITS       = 5,
    parameter LN_LUT_SIZE       = 20,
    parameter LN_EPSILON        = 1,
    parameter LN_OUT_BITS       = 8,    // Q4.4 output — matches DATA_BITS
    parameter LN_OUT_FRAC_BITS  = 4,
    // Gamma/beta files for layer norm learnable params
    parameter GammaFile      = "ln_gamma_1.mif",
    parameter BetaFile       = "ln_beta_1.mif"
)(
    input  clk,
    input  rstn,
    input  activation_function,                                     // passed to relu inside layer_norm
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat,

    output signed [NUM_NEURONS*LN_OUT_BITS-1:0] data_out_flat,     // Q4.4 per neuron
    output valid_out,
    output done
);

    //--------------------------------------------------------------------------
    // Neuron output width: DATA_BITS + WEIGHT_BITS + log2(NUM_FEATURES) + bias
    // Using DATA_BITS+WEIGHT_BITS+8 to match existing neuron port
    //--------------------------------------------------------------------------
    localparam NEURON_OUT_BITS = DATA_BITS + WEIGHT_BITS + 8;

    //--------------------------------------------------------------------------
    // Counter
    //--------------------------------------------------------------------------
    wire [31:0] counter;
    wire        counter_done;

    counter #(
        .END_COUNTER(NUM_FEATURES)
    ) layer_counter (
        .clk               (clk),
        .rstn              (rstn),
        .counter_out       (counter),
        .counter_donestatus(counter_done)
    );

    assign done = counter_done;

    //--------------------------------------------------------------------------
    // Raw neuron outputs (wider internal bus before layer norm)
    //--------------------------------------------------------------------------
    wire signed [NEURON_OUT_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];

    //--------------------------------------------------------------------------
    // Internal flat bus: all neuron outputs packed, sign-extended to LN_DATA_BITS
    // This is what gets fed into layer_norm as data_in
    // Each neuron output is sign-extended from NEURON_OUT_BITS to LN_DATA_BITS
    //--------------------------------------------------------------------------
    reg signed [NUM_NEURONS*LN_DATA_BITS-1:0] ln_data_in;

    // Layer norm gamma / beta (loaded from MIF files)
    // Intermediate arrays for file loading
    reg signed [LN_SCALE_BITS-1:0] gamma_arr [0:NUM_NEURONS-1];
    reg signed [LN_SCALE_BITS-1:0] beta_arr  [0:NUM_NEURONS-1];

    // Flat buses fed to layer_norm
    reg signed [NUM_NEURONS*LN_SCALE_BITS-1:0] ln_gamma;
    reg signed [NUM_NEURONS*LN_SCALE_BITS-1:0] ln_beta;

    integer g;
    initial begin
        $readmemb(GammaFile, gamma_arr);
        $readmemb(BetaFile,  beta_arr);

        // Pack array into flat bus
        for (g = 0; g < NUM_NEURONS; g = g + 1) begin
            ln_gamma[g*LN_SCALE_BITS +: LN_SCALE_BITS] = gamma_arr[g];
            ln_beta [g*LN_SCALE_BITS +: LN_SCALE_BITS] = beta_arr [g];
        end
    end

    //--------------------------------------------------------------------------
    // Layer norm valid_in: pulse for 1 cycle when counter_done fires
    // Register counter_done edge to create a clean 1-cycle pulse
    //--------------------------------------------------------------------------
    reg counter_done_r;
    reg ln_valid_in;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            counter_done_r <= 1'b0;
            ln_valid_in    <= 1'b0;
        end else begin
            counter_done_r <= counter_done;
            // Rising edge of counter_done → 1-cycle pulse to layer norm
            ln_valid_in    <= counter_done & ~counter_done_r;
        end
    end

    //--------------------------------------------------------------------------
    // Latch neuron outputs into ln_data_in when counter_done fires
    // Sign-extend each NEURON_OUT_BITS result to LN_DATA_BITS
    //--------------------------------------------------------------------------
    integer n;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ln_data_in <= {(NUM_NEURONS*LN_DATA_BITS){1'b0}};
        end else if (counter_done & ~counter_done_r) begin
            for (n = 0; n < NUM_NEURONS; n = n + 1) begin
                // Arithmetic sign extension: NEURON_OUT_BITS → LN_DATA_BITS
                ln_data_in[n*LN_DATA_BITS +: LN_DATA_BITS] <=
                    {{(LN_DATA_BITS-NEURON_OUT_BITS){neuron_outputs[n][NEURON_OUT_BITS-1]}},
                      neuron_outputs[n]};
            end
        end
    end

    //--------------------------------------------------------------------------
    // Layer norm instance
    // NUM_FEATURES here = NUM_NEURONS (we normalise across the neuron outputs)
    //--------------------------------------------------------------------------
    layer_norm #(
        .NUM_FEATURES      (NUM_NEURONS),
        .DATA_BITS         (LN_DATA_BITS),
        .DATA_FRAC_BITS    (LN_DATA_FRAC_BITS),
        .SCALE_BITS        (LN_SCALE_BITS),
        .FRAC_BITS         (LN_FRAC_BITS),
        .INV_SQRT_BITS     (LN_INV_SQRT_BITS),
        .INV_SQRT_FRAC_BITS(LN_INV_SQRT_FRAC),
        .VAR_BITS          (LN_VAR_BITS),
        .LUT_BITS          (LN_LUT_BITS),
        .LUT_SIZE          (LN_LUT_SIZE),
        .EPSILON           (LN_EPSILON),
        .OUT_BITS          (LN_OUT_BITS),
        .OUT_FRAC_BITS     (LN_OUT_FRAC_BITS)
    ) u_layer_norm (
        .clk      (clk),
        .rstn     (rstn),
        .valid_in (ln_valid_in),
        .act_en   (activation_function),
        .data_in  (ln_data_in),
        .gamma    (ln_gamma),
        .beta     (ln_beta),
        .valid_out(valid_out),
        .busy     (/* unused externally */),
        .data_out (data_out_flat)
    );

    //--------------------------------------------------------------------------
    // Neuron generate block
    //--------------------------------------------------------------------------
    generate
        if (NUM_NEURONS > 0) begin : neuron_0
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_0.mif"),
                .BiasFile  ("edge_encoder_b_1_0.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[0])
            );
        end

        if (NUM_NEURONS > 1) begin : neuron_1
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_1.mif"),
                .BiasFile  ("edge_encoder_b_1_1.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[1])
            );
        end

        if (NUM_NEURONS > 2) begin : neuron_2
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_2.mif"),
                .BiasFile  ("edge_encoder_b_1_2.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[2])
            );
        end

        if (NUM_NEURONS > 3) begin : neuron_3
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_3.mif"),
                .BiasFile  ("edge_encoder_b_1_3.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[3])
            );
        end

        if (NUM_NEURONS > 4) begin : neuron_4
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_4.mif"),
                .BiasFile  ("edge_encoder_b_1_4.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[4])
            );
        end

        if (NUM_NEURONS > 5) begin : neuron_5
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_5.mif"),
                .BiasFile  ("edge_encoder_b_1_5.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[5])
            );
        end

        if (NUM_NEURONS > 6) begin : neuron_6
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_6.mif"),
                .BiasFile  ("edge_encoder_b_1_6.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[6])
            );
        end

        if (NUM_NEURONS > 7) begin : neuron_7
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_7.mif"),
                .BiasFile  ("edge_encoder_b_1_7.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[7])
            );
        end

        if (NUM_NEURONS > 8) begin : neuron_8
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_8.mif"),
                .BiasFile  ("edge_encoder_b_1_8.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[8])
            );
        end

        if (NUM_NEURONS > 9) begin : neuron_9
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_9.mif"),
                .BiasFile  ("edge_encoder_b_1_9.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[9])
            );
        end

        if (NUM_NEURONS > 10) begin : neuron_10
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_10.mif"),
                .BiasFile  ("edge_encoder_b_1_10.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[10])
            );
        end

        if (NUM_NEURONS > 11) begin : neuron_11
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_11.mif"),
                .BiasFile  ("edge_encoder_b_1_11.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[11])
            );
        end

        if (NUM_NEURONS > 12) begin : neuron_12
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_12.mif"),
                .BiasFile  ("edge_encoder_b_1_12.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[12])
            );
        end

        if (NUM_NEURONS > 13) begin : neuron_13
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_13.mif"),
                .BiasFile  ("edge_encoder_b_1_13.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[13])
            );
        end

        if (NUM_NEURONS > 14) begin : neuron_14
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_14.mif"),
                .BiasFile  ("edge_encoder_b_1_14.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[14])
            );
        end

        if (NUM_NEURONS > 15) begin : neuron_15
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_15.mif"),
                .BiasFile  ("edge_encoder_b_1_15.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[15])
            );
        end

        if (NUM_NEURONS > 16) begin : neuron_16
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_16.mif"),
                .BiasFile  ("edge_encoder_b_1_16.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[16])
            );
        end

        if (NUM_NEURONS > 17) begin : neuron_17
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_17.mif"),
                .BiasFile  ("edge_encoder_b_1_17.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[17])
            );
        end

        if (NUM_NEURONS > 18) begin : neuron_18
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_18.mif"),
                .BiasFile  ("edge_encoder_b_1_18.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[18])
            );
        end

        if (NUM_NEURONS > 19) begin : neuron_19
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_19.mif"),
                .BiasFile  ("edge_encoder_b_1_19.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[19])
            );
        end

        if (NUM_NEURONS > 20) begin : neuron_20
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_20.mif"),
                .BiasFile  ("edge_encoder_b_1_20.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[20])
            );
        end

        if (NUM_NEURONS > 21) begin : neuron_21
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_21.mif"),
                .BiasFile  ("edge_encoder_b_1_21.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[21])
            );
        end

        if (NUM_NEURONS > 22) begin : neuron_22
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_22.mif"),
                .BiasFile  ("edge_encoder_b_1_22.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[22])
            );
        end

        if (NUM_NEURONS > 23) begin : neuron_23
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_23.mif"),
                .BiasFile  ("edge_encoder_b_1_23.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[23])
            );
        end

        if (NUM_NEURONS > 24) begin : neuron_24
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_24.mif"),
                .BiasFile  ("edge_encoder_b_1_24.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[24])
            );
        end

        if (NUM_NEURONS > 25) begin : neuron_25
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_25.mif"),
                .BiasFile  ("edge_encoder_b_1_25.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[25])
            );
        end

        if (NUM_NEURONS > 26) begin : neuron_26
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_26.mif"),
                .BiasFile  ("edge_encoder_b_1_26.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[26])
            );
        end

        if (NUM_NEURONS > 27) begin : neuron_27
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_27.mif"),
                .BiasFile  ("edge_encoder_b_1_27.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[27])
            );
        end

        if (NUM_NEURONS > 28) begin : neuron_28
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_28.mif"),
                .BiasFile  ("edge_encoder_b_1_28.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[28])
            );
        end

        if (NUM_NEURONS > 29) begin : neuron_29
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_29.mif"),
                .BiasFile  ("edge_encoder_b_1_29.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[29])
            );
        end

        if (NUM_NEURONS > 30) begin : neuron_30
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_30.mif"),
                .BiasFile  ("edge_encoder_b_1_30.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[30])
            );
        end

        if (NUM_NEURONS > 31) begin : neuron_31
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES), .DATA_BITS(DATA_BITS),
                .WEIGHT_BITS(WEIGHT_BITS),   .BIAS_BITS(BIAS_BITS),
                .WeightFile("edge_encoder_w_1_31.mif"),
                .BiasFile  ("edge_encoder_b_1_31.mif")
            ) inst (
                .clk(clk), .rstn(rstn),
                .activation_function(activation_function),
                .data_in_flat(data_in_flat), .counter(counter),
                .data_out(neuron_outputs[31])
            );
        end

    endgenerate

endmodule
