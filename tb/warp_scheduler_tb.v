// =============================================================
// warp_scheduler_tb.v
// Verifies reset -> warp0 first, then strict alternation.
// =============================================================

`timescale 1ns/1ps

module warp_scheduler_tb;

    reg clk, rst_n;
    wire warp_select;

    integer errors;
    integer i;
    reg expected;

    warp_scheduler dut (.clk(clk), .rst_n(rst_n), .warp_select(warp_select));

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        clk = 0; rst_n = 0;

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;
        @(negedge clk); // rst_n was raised just before this edge, so the
                         // reset-held value (0) has already toggled once -> 1

        if (warp_select !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: post-reset warp_select expected=1 got=%b", warp_select);
        end

        expected = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            if (warp_select !== expected) begin
                errors = errors + 1;
                $display("FAIL: cycle %0d expected=%b got=%b", i, expected, warp_select);
            end
            expected = ~expected;
        end

        if (errors == 0)
            $display("WARP_SCHEDULER_TB: ALL TESTS PASSED");
        else
            $display("WARP_SCHEDULER_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
