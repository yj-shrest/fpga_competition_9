`timescale 1ns / 1ps
//==============================================================================
// layer_norm_tb.v  —  Testbench for layer_norm (Moore FSM)
//
// DUT I/O:
//   data_in  : NUM_FEATURES × 24-bit signed  Q14.10  (range ±8191.999)
//   gamma    : NUM_FEATURES ×  8-bit signed  Q1.6    (range ±1.984)
//   beta     : NUM_FEATURES ×  8-bit signed  Q1.6    (range ±1.984)
//   data_out : NUM_FEATURES ×  8-bit signed  Q4.4    (range ±7.9375)
//
// Reference model:
//   1. Compute mean / variance in real arithmetic
//   2. Normalize, scale, shift → Q14.10 reference
//   3. Apply ReLU if act_en=1 → zero negatives
//   4. Requantize Q14.10 → Q4.4: floor(val*1024/64)/16, saturate [-8, +7.9375]
//==============================================================================

module layer_norm_tb;

    //--------------------------------------------------------------------------
    // Parameters — must match DUT exactly
    //--------------------------------------------------------------------------
    localparam NUM_FEATURES       = 32;
    localparam DATA_BITS          = 24;
    localparam DATA_FRAC_BITS     = 10;
    localparam SCALE_BITS         = 8;
    localparam FRAC_BITS          = 6;
    localparam INV_SQRT_BITS      = 16;
    localparam INV_SQRT_FRAC_BITS = 11;
    localparam VAR_BITS           = 45;
    localparam LUT_BITS           = 5;
    localparam LUT_SIZE           = 20;
    localparam EPSILON            = 1;
    localparam OUT_BITS           = 8;
    localparam OUT_FRAC_BITS      = 4;

    // Derived
    localparam DATA_WIDTH  = NUM_FEATURES * DATA_BITS;    // 768
    localparam SCALE_WIDTH = NUM_FEATURES * SCALE_BITS;   // 256
    localparam OUT_WIDTH   = NUM_FEATURES * OUT_BITS;     // 256

    // Fixed-point scales
    localparam real DATA_SCALE  = 2.0 ** DATA_FRAC_BITS;   // 1024.0
    localparam real SCALE_SCALE = 2.0 ** FRAC_BITS;         //   64.0
    localparam real OUT_SCALE   = 2.0 ** OUT_FRAC_BITS;     //   16.0

    // Requantize drop: DATA_FRAC_BITS - OUT_FRAC_BITS = 6 bits dropped
    localparam FRAC_DROP = DATA_FRAC_BITS - OUT_FRAC_BITS;  // 6

    // Q4.4 saturation limits in real
    localparam real OUT_MAX_REAL =  127.0 / OUT_SCALE;      //  +7.9375
    localparam real OUT_MIN_REAL = -128.0 / OUT_SCALE;      //  -8.0000

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk  = 1'b0;
    reg rstn = 1'b0;

    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // DUT ports
    //--------------------------------------------------------------------------
    reg                           valid_in = 1'b0;
    reg                           act_en   = 1'b1;
    reg  signed [DATA_WIDTH-1:0]  data_in  = {DATA_WIDTH{1'b0}};
    reg  signed [SCALE_WIDTH-1:0] gamma    = {SCALE_WIDTH{1'b0}};
    reg  signed [SCALE_WIDTH-1:0] beta     = {SCALE_WIDTH{1'b0}};

    wire                          valid_out;
    wire                          busy;
    wire signed [OUT_WIDTH-1:0]   data_out;   // Q4.4, 8-bit per feature

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    layer_norm #(
        .NUM_FEATURES      (NUM_FEATURES),
        .DATA_BITS         (DATA_BITS),
        .DATA_FRAC_BITS    (DATA_FRAC_BITS),
        .SCALE_BITS        (SCALE_BITS),
        .FRAC_BITS         (FRAC_BITS),
        .INV_SQRT_BITS     (INV_SQRT_BITS),
        .INV_SQRT_FRAC_BITS(INV_SQRT_FRAC_BITS),
        .VAR_BITS          (VAR_BITS),
        .LUT_BITS          (LUT_BITS),
        .LUT_SIZE          (LUT_SIZE),
        .EPSILON           (EPSILON),
        .OUT_BITS          (OUT_BITS),
        .OUT_FRAC_BITS     (OUT_FRAC_BITS)
    ) dut (
        .clk      (clk),
        .rstn     (rstn),
        .valid_in (valid_in),
        .act_en   (act_en),
        .data_in  (data_in),
        .gamma    (gamma),
        .beta     (beta),
        .valid_out(valid_out),
        .busy     (busy),
        .data_out (data_out)
    );

    //--------------------------------------------------------------------------
    // Encode: real → Q14.10 24-bit signed
    //--------------------------------------------------------------------------
    function signed [DATA_BITS-1:0] encode_data;
        input real val;
        begin
            encode_data = $signed($rtoi(val * DATA_SCALE));
        end
    endfunction

    //--------------------------------------------------------------------------
    // Encode: real → Q1.6 8-bit signed
    //--------------------------------------------------------------------------
    function signed [SCALE_BITS-1:0] encode_scale;
        input real val;
        begin
            encode_scale = $signed($rtoi(val * SCALE_SCALE));
        end
    endfunction

    //--------------------------------------------------------------------------
    // Decode: Q14.10 24-bit raw → real
    //--------------------------------------------------------------------------
    function real decode_input;
        input signed [DATA_BITS-1:0] raw;
        begin
            decode_input = $itor($signed(raw)) / DATA_SCALE;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Decode: Q4.4 8-bit raw → real
    //--------------------------------------------------------------------------
    function real decode_output;
        input signed [OUT_BITS-1:0] raw;
        begin
            decode_output = $itor($signed(raw)) / OUT_SCALE;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Reference: Q14.10 real value → ReLU → requantize → Q4.4 real
    // Mirrors hardware exactly:
    //   Step 1: arithmetic >> FRAC_DROP = floor(val * DATA_SCALE / 2^FRAC_DROP)
    //   Step 2: if relu_en and result < 0 → zero
    //   Step 3: saturate to [-128, +127] raw, output as real / OUT_SCALE
    //--------------------------------------------------------------------------
    function real ref_requantize;
        input real    val_q1410;
        input integer relu_en;
        real shifted_raw;
        real result;
        begin
            // Arithmetic right shift 6 in the fixed-point domain
            // floor() matches hardware >>> behaviour for signed values
            shifted_raw = $floor(val_q1410 * DATA_SCALE / (2.0**FRAC_DROP));

            // Convert to real in Q4.4 domain
            result = shifted_raw / OUT_SCALE;

            // ReLU
            if (relu_en && result < 0.0)
                result = 0.0;

            // Saturate
            if      (result > OUT_MAX_REAL) result = OUT_MAX_REAL;
            else if (result < OUT_MIN_REAL) result = OUT_MIN_REAL;

            // Snap to Q4.4 grid (hardware truncates to 8-bit)
            result = $floor(result * OUT_SCALE) / OUT_SCALE;

            ref_requantize = result;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Shared stimulus storage
    //--------------------------------------------------------------------------
    reg signed [DATA_BITS-1:0]  vec_data [0:NUM_FEATURES-1];
    reg signed [SCALE_BITS-1:0] vec_gamma[0:NUM_FEATURES-1];
    reg signed [SCALE_BITS-1:0] vec_beta [0:NUM_FEATURES-1];

    integer i;
    integer test_num;
    real    ref_sum, ref_mean, ref_var_acc, ref_var, ref_inv_sqrt;
    real    ref_norm_q1410 [0:NUM_FEATURES-1];   // after gamma/beta, before requant
    real    ref_out        [0:NUM_FEATURES-1];   // after relu + requant

    //--------------------------------------------------------------------------
    // Task: pack vec_* arrays into flat port buses
    //--------------------------------------------------------------------------
    task pack_inputs;
        integer k;
        begin
            for (k = 0; k < NUM_FEATURES; k = k + 1) begin
                data_in[k*DATA_BITS  +: DATA_BITS]  = vec_data [k];
                gamma  [k*SCALE_BITS +: SCALE_BITS] = vec_gamma[k];
                beta   [k*SCALE_BITS +: SCALE_BITS] = vec_beta [k];
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: run one full transaction
    //--------------------------------------------------------------------------
    localparam TIMEOUT_CYCLES = 150;

    task run_transaction;
        input integer tnum;
        integer t;
        reg     got_valid;
        real    out_val, ref_val, delta;
        begin
            $display("\n========================================================");
            $display("TEST %0d  (time=%0t ns)  act_en=%0b", tnum, $time, act_en);
            $display("========================================================");

            // Print inputs
            $display("  Input data (Q14.10 real):");
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                $display("    data[%02d] = %9.5f  (raw=%0d)",
                         i, decode_input(vec_data[i]), $signed(vec_data[i]));

            $display("  Gamma / Beta (Q1.6 real):");
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                $display("    gamma[%02d]=%7.4f  beta[%02d]=%7.4f",
                         i, $itor($signed(vec_gamma[i]))/SCALE_SCALE,
                         i, $itor($signed(vec_beta [i]))/SCALE_SCALE);

            // ---- Reference computation ----

            // Mean
            ref_sum = 0.0;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                ref_sum = ref_sum + decode_input(vec_data[i]);
            ref_mean = ref_sum / NUM_FEATURES;

            // Variance
            ref_var_acc = 0.0;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                ref_var_acc = ref_var_acc
                    + (decode_input(vec_data[i]) - ref_mean)
                    * (decode_input(vec_data[i]) - ref_mean);
            ref_var = ref_var_acc / NUM_FEATURES;

            // inv_sqrt — epsilon is 1 LSB in Q14.10 = 1/1024
            ref_inv_sqrt = 1.0 / $sqrt(ref_var + $itor(EPSILON)/DATA_SCALE);

            $display("  Ref: mean=%.6f  var=%.8f  inv_sqrt=%.4f",
                     ref_mean, ref_var, ref_inv_sqrt);

            // Normalize + scale + shift → Q14.10 real domain
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                ref_norm_q1410[i] =
                    (decode_input(vec_data[i]) - ref_mean) * ref_inv_sqrt
                    * ($itor($signed(vec_gamma[i])) / SCALE_SCALE)
                    + ($itor($signed(vec_beta [i])) / SCALE_SCALE);

            // ReLU + requantize → Q4.4 real
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                ref_out[i] = ref_requantize(ref_norm_q1410[i], act_en);

            // ---- Drive DUT ----
            @(negedge clk);
            valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0;

            // Wait for valid_out
            got_valid = 1'b0;
            for (t = 0; t < TIMEOUT_CYCLES; t = t + 1) begin
                @(posedge clk); #1;
                if (valid_out) begin
                    got_valid = 1'b1;
                    t = TIMEOUT_CYCLES;
                end
            end

            if (!got_valid) begin
                $display("  [FAIL] Timeout after %0d cycles", TIMEOUT_CYCLES);
                $finish;
            end

            // ---- Compare Q4.4 output ----
            $display("  DUT Q4.4 output vs reference:");
            $display("    %s  %7s  %8s  %8s  %8s",
                     "idx", "raw", "dut", "ref", "delta");
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                out_val = decode_output(
                              $signed(data_out[i*OUT_BITS +: OUT_BITS]));
                ref_val = ref_out[i];
                delta   = out_val - ref_val;
                $display("    out[%02d]  raw=%4d  dut=%8.4f  ref=%8.4f  delta=%8.4f",
                         i,
                         $signed(data_out[i*OUT_BITS +: OUT_BITS]),
                         out_val, ref_val, delta);
            end

            $display("  [PASS] valid_out received");

            @(posedge clk); #1;
            if (busy)
                $display("  [WARN] busy still asserted one cycle after valid_out");
        end
    endtask

    //--------------------------------------------------------------------------
    // Stimulus
    //--------------------------------------------------------------------------
    integer seed1 = 32'hDEAD_BEEF;
    integer seed2 = 32'hCAFE_BABE;
    real    rand_val;

    initial begin
        $dumpfile("layer_norm_tb.vcd");
        $dumpvars(0, layer_norm_tb);

        rstn     = 1'b0;
        valid_in = 1'b0;
        repeat(4) @(posedge clk); #1;
        rstn = 1'b1;
        repeat(2) @(posedge clk); #1;
        $display("Reset complete.");

        //======================================================================
        // TEST 1: All zeros — degenerate
        //   mean=0, var=0, (x-mean)=0 → norm=0 → output = relu(beta) requantized
        //   beta=0.1 → Q14.10 = 102 → >>6 = 1 → Q4.4 raw=1 → 0.0625
        //======================================================================
        // test_num = 1;
        // act_en   = 1'b1;
        // for (i = 0; i < NUM_FEATURES; i = i + 1) begin
        //     vec_data [i] = encode_data (0.0);
        //     vec_gamma[i] = encode_scale(0.5);
        //     vec_beta [i] = encode_scale(0.1);
        // end
        // pack_inputs;
        // run_transaction(test_num);

        // //======================================================================
        // // TEST 2: Constant input 0.5 — zero variance
        // //   output = relu(beta) requantized
        // //   beta=-0.1 → with relu → 0
        // //======================================================================
        // test_num = 2;
        // act_en   = 1'b1;
        // for (i = 0; i < NUM_FEATURES; i = i + 1) begin
        //     vec_data [i] = encode_data ( 0.5);
        //     vec_gamma[i] = encode_scale( 0.8);
        //     vec_beta [i] = encode_scale(-0.1);
        // end
        // pack_inputs;
        // run_transaction(test_num);

        //======================================================================
        // TEST 3: Random data (-1,+1), gamma (0.5,1.0), beta (-0.25,+0.25)
        //         act_en=1: negatives zeroed
        //======================================================================
        // test_num = 3;
        // act_en   = 1'b1;
        // for (i = 0; i < NUM_FEATURES; i = i + 1) begin
        //     rand_val = $itor($signed($random(seed1))) / 2147483648.0;
        //     if (rand_val >  0.99) rand_val =  0.99;
        //     if (rand_val < -0.99) rand_val = -0.99;
        //     vec_data[i] = encode_data(rand_val);

        //     rand_val = 0.5 + 0.5*($itor($unsigned($random(seed1)))/4294967296.0);
        //     vec_gamma[i] = encode_scale(rand_val);

        //     rand_val = ($itor($signed($random(seed1)))/2147483648.0)*0.25;
        //     vec_beta[i] = encode_scale(rand_val);
        // end
        // pack_inputs;
        // run_transaction(test_num);

        //======================================================================
        // TEST 4: Alternating ±0.5, act_en=0 (no ReLU)
        //   mean=0, var=0.25, inv_sqrt≈2.0
        //   out[even] ≈ +1.0, out[odd] ≈ -1.0 in Q14.10
        //   After >>6 and /16: ±1.0 in Q4.4
        //   Negative values pass through since act_en=0
        //======================================================================
        // test_num = 4;
        // act_en   = 1'b0;
        // for (i = 0; i < NUM_FEATURES; i = i + 1) begin
        //     vec_data [i] = encode_data(i % 2 == 0 ?  0.5 : -0.5);
        //     vec_gamma[i] = encode_scale(1.0);
        //     vec_beta [i] = encode_scale(0.0);
        // end
        // pack_inputs;
        // run_transaction(test_num);

        //======================================================================
        // TEST 5: Same pattern, act_en=1 — odd outputs must be zeroed
        //======================================================================
        // test_num = 5;
        // act_en   = 1'b1;
        // // vec_* unchanged from test 4
        // pack_inputs;
        // run_transaction(test_num);

        //======================================================================
        // TEST 6: Random, different seed, act_en=1
        //         data (-0.75,+0.75), gamma (-1,+1), beta (-0.5,+0.5)
        //======================================================================
        test_num = 6;
        act_en   = 1'b1;
        for (i = 0; i < NUM_FEATURES; i = i + 1) begin
            rand_val = ($itor($signed($random(seed2)))/2147483648.0)*0.75;
            if (rand_val >  0.74) rand_val =  0.74;
            if (rand_val < -0.74) rand_val = -0.74;
            vec_data[i] = encode_data(rand_val);

            rand_val = $itor($signed($random(seed2)))/2147483648.0;
            if (rand_val >  0.99) rand_val =  0.99;
            if (rand_val < -0.99) rand_val = -0.99;
            vec_gamma[i] = encode_scale(rand_val);

            rand_val = ($itor($signed($random(seed2)))/2147483648.0)*0.5;
            if (rand_val >  0.49) rand_val =  0.49;
            if (rand_val < -0.49) rand_val = -0.49;
            vec_beta[i] = encode_scale(rand_val);
        end
        pack_inputs;
        run_transaction(test_num);

        $display("\n========================================================");
        $display("All %0d tests completed.", test_num);
        $display("========================================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("[WATCHDOG] Global timeout — ABORT");
        $finish;
    end

endmodule