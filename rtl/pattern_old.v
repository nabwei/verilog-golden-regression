`timescale 1ns/1ps
module pattern_old #(
    parameter integer BAR_WIDTH = 4
) (
    input wire pixel_clock,
    input wire reset,
    input wire enable,
    output reg [7:0] pixel
);
    integer position;

    always @(posedge pixel_clock) begin
        if (reset) begin
            position <= 0;
            pixel <= 0;
        end else if (enable) begin
            case (position / BAR_WIDTH)
                0: pixel <= 8'h20;
                1: pixel <= 8'h80;
                2: pixel <= 8'he0;
            endcase
            if (position == 3 * BAR_WIDTH - 1)
                position <= 0;
            else
                position <= position + 1;
        end
    end
endmodule
