module layer_norm_inv_sqrt #(
    parameter VAR_BITS      = 45,
    parameter VAR_FRAC_BITS = 15,
    parameter LUT_BITS      = 5,        // 2^5=32 entries allocated in memory
    parameter LUT_SIZE      = 20,       // only 20 entries populated by generator
    parameter OUT_BITS      = 16,
    parameter OUT_FRAC_BITS = 11,       // Q5.11
    parameter real VAR_MIN_REAL = 0.01,
    parameter real VAR_MAX_REAL = 1024.0
)(
    input  clk,
    input  rstn,
    input  valid_in,
    input  [VAR_BITS-1:0] variance_in,

    output reg valid_out,
    output reg [OUT_BITS-1:0] inv_sqrt_out
);

    reg [OUT_BITS-1:0] lut [0:(1<<LUT_BITS)-1];

    initial begin
        $readmemb("inv_sqrt_lut.mem", lut);
    end

    localparam IDLE = 2'd0;
    localparam ADDR = 2'd1;
    localparam LUTR = 2'd2;
    localparam OUT  = 2'd3;

    reg [1:0]          state;
    reg [LUT_BITS-1:0] addr;

    // Address function — geometric mapping, clamped to LUT_SIZE-1
    function [LUT_BITS-1:0] variance_to_lut_addr;
        input [VAR_BITS-1:0] var_in;
        real var_r;
        real log_ratio;
        real lut_idx;
        begin
            var_r = $itor(var_in) / (2.0 ** VAR_FRAC_BITS);

            // Clamp to generator range
            if (var_r < VAR_MIN_REAL) var_r = VAR_MIN_REAL;
            if (var_r > VAR_MAX_REAL) var_r = VAR_MAX_REAL;

            // Geometric index — matches generator: r = (VAR_MAX/VAR_MIN)^(1/(LUT_SIZE-1))
            log_ratio = $ln(var_r     / VAR_MIN_REAL)
                      / $ln(VAR_MAX_REAL / VAR_MIN_REAL);

            // Scale to populated entries only (0 to LUT_SIZE-1 = 0 to 19)
            lut_idx = log_ratio * (LUT_SIZE - 1);

            if (lut_idx < 0.0)            lut_idx = 0.0;
            if (lut_idx > LUT_SIZE - 1)   lut_idx = LUT_SIZE - 1;

            variance_to_lut_addr = $rtoi(lut_idx);
        end
    endfunction

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state        <= IDLE;
            valid_out    <= 0;
            inv_sqrt_out <= 0;
            addr         <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 0;
                    if (valid_in)
                        state <= ADDR;
                end

                ADDR: begin
                    addr  <= variance_to_lut_addr(variance_in);
                    state <= LUTR;
                end

                LUTR: begin
                    inv_sqrt_out <= lut[addr];
                    state        <= OUT;
                end

                OUT: begin
                    valid_out <= 1;
                    state     <= IDLE;
                end
            endcase
        end
    end

endmodule