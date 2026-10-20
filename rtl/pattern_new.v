`timescale 1ns/1ps
module pattern_new #(
    parameter integer BAR_WIDTH = 4,
    parameter integer MUTATION = 0
) (
    input wire pixel_clock,
    input wire reset,
    input wire enable,
    output reg [7:0] pixel
);
    integer offset;
    reg [1:0] bar;

    always @(posedge pixel_clock) begin
        if (reset) begin
            offset <= 0;
            bar <= 0;
            pixel <= (MUTATION == 3) ? 8'hff : 8'h00;
        end else if (enable) begin
            case (bar)
                0: pixel <= 8'h20;
                1: pixel <= (MUTATION == 2) ? 8'h81 : 8'h80;
                2: pixel <= 8'he0;
                default: pixel <= 8'h00;
            endcase
            if (offset == BAR_WIDTH - 1 + ((MUTATION == 1) ? 1 : 0)) begin
                offset <= 0;
                bar <= (bar == 2) ? 0 : bar + 1'b1;
            end else begin
                offset <= offset + 1;
            end
        end
    end
endmodule
