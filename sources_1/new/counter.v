`timescale 1ns / 1ps

module counter #(parameter END_COUNTER = 32'd0)
(
    input clk,
    input rstn,
    output reg [31:0] counter_out,
    output reg counter_donestatus
);

always @(posedge clk) begin
    if (!rstn) begin
        counter_out        <= 32'd0;
        counter_donestatus <= 1'b0;
    end
    else begin
        if (counter_out >= END_COUNTER) begin
            counter_out        <= END_COUNTER;
            counter_donestatus <= 1'b1;
        end
        else begin
            counter_out        <= counter_out + 1'b1;
            counter_donestatus <= 1'b0;

            // $display("[%0t] Counter: counter_out = %d", $time, counter_out);
        end
    end
end

endmodule
