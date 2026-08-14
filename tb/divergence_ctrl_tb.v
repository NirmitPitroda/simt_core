// =============================================================
// divergence_ctrl_tb.v
// Drives divergence_ctrl.v directly (no full pipeline) to check:
//   1. Reset state: active_mask = 4'b1111 for both warps.
//   2. A divergent branch (lanes 0,2 take / skip; lanes 1,3 don't)
//      correctly narrows active_mask to the not-taken lanes.
//   3. Non-branch instructions leave active_mask unchanged.
//   4. Reaching branch_target reconverges: active_mask returns to
//      its pre-branch value.
//   5. Warp0 and warp1 masks/stacks are independent of each other.
//   6. A uniform (non-divergent) branch (all active lanes take it)
//      still pushes/reconverges correctly with no false split.
// =============================================================

`timescale 1ns/1ps

module divergence_ctrl_tb;

    reg clk, rst_n;
    reg fetched_warp;
    reg [31:0] current_pc;
    reg is_branch;
    reg [11:0] immediate;
    reg lane0_zero, lane1_zero, lane2_zero, lane3_zero;

    wire [3:0] active_mask;
    wire branch_taken;
    wire [31:0] branch_target;
    wire branch_warp;

    integer errors;

    divergence_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .fetched_warp(fetched_warp),
        .current_pc(current_pc),
        .is_branch(is_branch),
        .immediate(immediate),
        .lane0_zero(lane0_zero), .lane1_zero(lane1_zero),
        .lane2_zero(lane2_zero), .lane3_zero(lane3_zero),
        .active_mask(active_mask),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .branch_warp(branch_warp)
    );

    always #5 clk = ~clk;

    task check_mask;
        input [127:0] name;
        input [3:0] expected;
        begin
            if (active_mask !== expected) begin
                errors = errors + 1;
                $display("FAIL[%0s] exp=%b got=%b", name, expected, active_mask);
            end else begin
                $display("PASS[%0s] active_mask=%b", name, active_mask);
            end
        end
    endtask

    // Drives one instruction for `fetched_warp` and advances one clock.
    task step;
        input        w;
        input [31:0] pc;
        input        br;
        input [11:0] imm;
        input        z0, z1, z2, z3;
        begin
            fetched_warp = w;
            current_pc   = pc;
            is_branch    = br;
            immediate    = imm;
            lane0_zero   = z0; lane1_zero = z1; lane2_zero = z2; lane3_zero = z3;
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; rst_n = 0;
        fetched_warp = 0; current_pc = 0; is_branch = 0; immediate = 0;
        lane0_zero = 0; lane1_zero = 0; lane2_zero = 0; lane3_zero = 0;

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---- Reset state ----
        fetched_warp = 0; #1;
        check_mask("warp0 reset mask", 4'b1111);
        fetched_warp = 1; #1;
        check_mask("warp1 reset mask", 4'b1111);

        // ---- Warp0: divergent branch at pc=0, target=pc+8 ----
        // lane0,lane2 zero=1 (condition true -> skip); lane1,lane3 zero=0 (fall through)
        step(1'b0, 32'd0, 1'b1, 12'd8, 1'b1, 1'b0, 1'b1, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 post-branch", 4'b1010);

        // ---- Warp0: a non-branch instruction mid-block — mask must hold ----
        step(1'b0, 32'd4, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 mid-block", 4'b1010);

        // ---- Warp1: independent — should still be full mask ----
        fetched_warp = 1; #1;
        check_mask("w1 unaffected", 4'b1111);

        // ---- Warp0: reach branch_target (pc=8) — reconverge ----
        step(1'b0, 32'd8, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 reconverged", 4'b1111);

        // ---- Warp1: uniform (non-divergent) branch — all active lanes take it ----
        step(1'b1, 32'd0, 1'b1, 12'd8, 1'b1, 1'b1, 1'b1, 1'b1);
        fetched_warp = 1; #1;
        check_mask("w1 uniform-take", 4'b0000);

        step(1'b1, 32'd4, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 1; #1;
        check_mask("w1 mid-skip", 4'b0000);

        step(1'b1, 32'd8, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 1; #1;
        check_mask("w1 reconverged", 4'b1111);

        // ---- Warp0: nested divergence ----
        // Outer branch at pc=100 -> target=116: lane3 skips (zero=1), 0/1/2 fall through
        step(1'b0, 32'd100, 1'b1, 12'd16, 1'b0, 1'b0, 1'b0, 1'b1);
        fetched_warp = 0; #1;
        check_mask("w0 outer-branch", 4'b0111);

        // Inner branch at pc=104 -> target=112: lane1 skips (zero=1), 0/2 fall through (lane3 already inactive)
        step(1'b0, 32'd104, 1'b1, 12'd8, 1'b0, 1'b1, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 inner-branch", 4'b0101);

        // pc=108: still inside inner block
        step(1'b0, 32'd108, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 inner-block", 4'b0101);

        // pc=112: reconverge inner (lane1 rejoins)
        step(1'b0, 32'd112, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 inner-reconv", 4'b0111);

        // pc=116: reconverge outer (lane3 rejoins)
        step(1'b0, 32'd116, 1'b0, 12'd0, 1'b0, 1'b0, 1'b0, 1'b0);
        fetched_warp = 0; #1;
        check_mask("w0 outer-reconv", 4'b1111);

        if (errors == 0)
            $display("DIVERGENCE_CTRL_TB: ALL TESTS PASSED");
        else
            $display("DIVERGENCE_CTRL_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
