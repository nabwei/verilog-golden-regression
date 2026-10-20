`timescale 1ns/1ps
module compare_patterns;
    parameter integer BAR_WIDTH = 4;
    parameter integer MUTATION = 0;
    reg pixel_clock = 0;
    reg reset = 1;
    reg enable = 0;
    wire [7:0] old_pixel;
    wire [7:0] new_pixel;
    reg [7:0] expected_pixel = 0;
    integer expected_position = 0;
    integer cycle;

    pattern_old #(.BAR_WIDTH(BAR_WIDTH)) golden (
        pixel_clock, reset, enable, old_pixel
    );
    pattern_mutant #(.BAR_WIDTH(BAR_WIDTH), .MUTATION(MUTATION)) candidate (
        pixel_clock, reset, enable, new_pixel
    );
    always #5 pixel_clock = ~pixel_clock;

    initial begin
        for (cycle = 0; cycle < 180; cycle = cycle + 1) begin
            reset = (cycle < 2 || cycle == 53 || cycle == 82 || cycle == 109);
            enable = (cycle % 7 != 3 && cycle % 7 != 4);
            if (reset) begin
                expected_position = 0;
                expected_pixel = 0;
            end else if (enable) begin
                case (expected_position / BAR_WIDTH)
                    0: expected_pixel = 8'h20;
                    1: expected_pixel = 8'h80;
                    2: expected_pixel = 8'he0;
                endcase
                expected_position = (expected_position + 1) % (3 * BAR_WIDTH);
            end
            @(posedge pixel_clock);
            #1;
            if (old_pixel !== new_pixel || old_pixel !== expected_pixel) begin
                $display("MISMATCH cycle=%0d reset=%b enable=%b old=%h new=%h expected=%h",
                    cycle, reset, enable, old_pixel, new_pixel, expected_pixel);
                $fatal(1, "First mismatch");
            end
            @(negedge pixel_clock);
        end
        $display("PASS cycles=180 bar_width=%0d", BAR_WIDTH);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "TIMEOUT");
    end
endmodule
