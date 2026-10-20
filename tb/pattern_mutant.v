`timescale 1ns/1ps
module pattern_mutant #(
    parameter integer BAR_WIDTH = 4,
    parameter integer MUTATION = 0
) (
    input wire pixel_clock,
    input wire reset,
    input wire enable,
    output wire [7:0] pixel
);
    localparam integer TEST_WIDTH = (MUTATION == 1) ? BAR_WIDTH + 1 : BAR_WIDTH;
    wire [7:0] normal_pixel;
    pattern_new #(.BAR_WIDTH(TEST_WIDTH)) design_under_test (
        pixel_clock, reset, enable, normal_pixel
    );
    assign pixel = (MUTATION == 3 && reset) ? 8'hff :
                   (MUTATION == 2 && normal_pixel == 8'h80) ? 8'h81 : normal_pixel;
endmodule
