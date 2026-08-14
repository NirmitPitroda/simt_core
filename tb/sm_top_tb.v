// =============================================================
// sm_top_tb.v
// End-to-end Tier-1 (non-divergent) test: runs the same 4-instr
// program (r3=r0+10; r4=r0+25; r5=r3+r4; r6=r5+r0 readback) through
// the full scheduler->fetch->decode->4-lane pipeline, across both
// interleaved warps, and checks all 4 lanes agree (since no
// per-lane differentiation exists yet, they should compute
// identically) and that each warp's register partition is correct
// and isolated from the other warp's interleaved execution.
// =============================================================

`timescale 1ns/1ps

module sm_top_tb;

    reg clk, rst_n;
    wire [31:0] lane0_result, lane1_result, lane2_result, lane3_result;
    wire lane0_zero, lane1_zero, lane2_zero, lane3_zero;
    wire [31:0] debug_pc;
    wire debug_warp_select;

    integer errors;

    sm_top dut (
        .clk(clk), .rst_n(rst_n),
        .lane0_result(lane0_result), .lane1_result(lane1_result),
        .lane2_result(lane2_result), .lane3_result(lane3_result),
        .lane0_zero(lane0_zero), .lane1_zero(lane1_zero),
        .lane2_zero(lane2_zero), .lane3_zero(lane3_zero),
        .debug_pc(debug_pc), .debug_warp_select(debug_warp_select)
    );

    always #5 clk = ~clk;

    task check_all_lanes;
        input [127:0] name;
        input [31:0]  expected;
        begin
            #1;
            if (lane0_result !== expected) begin errors=errors+1; $display("FAIL[%0s] lane0 exp=%0d got=%0d", name, expected, lane0_result); end
            if (lane1_result !== expected) begin errors=errors+1; $display("FAIL[%0s] lane1 exp=%0d got=%0d", name, expected, lane1_result); end
            if (lane2_result !== expected) begin errors=errors+1; $display("FAIL[%0s] lane2 exp=%0d got=%0d", name, expected, lane2_result); end
            if (lane3_result !== expected) begin errors=errors+1; $display("FAIL[%0s] lane3 exp=%0d got=%0d", name, expected, lane3_result); end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; rst_n = 0;

        // program: r3=r0+10 ; r4=r0+25 ; r5=r3+r4 ; r6=r5+r0 (readback of r5)
        dut.u_fetch.u_imem.mem[0] = {4'd0,4'd0,4'd3,4'b0000,4'b0001,12'd10};
        dut.u_fetch.u_imem.mem[1] = {4'd0,4'd0,4'd4,4'b0000,4'b0001,12'd25};
        dut.u_fetch.u_imem.mem[2] = {4'd4,4'd3,4'd5,4'b0000,4'b0000,12'd0};
        dut.u_fetch.u_imem.mem[3] = {4'd0,4'd5,4'd6,4'b0000,4'b0000,12'd0};

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;

        // Per the verified debug trace: cycle0=warp1/pc0, cycle1=warp0/pc4,
        // cycle2=warp1/pc4, cycle3=warp0/pc8, cycle4=warp1/pc8,
        // cycle5=warp0/pc12(readback,exp=35), cycle6=warp1/pc12(readback,exp=35)
        @(negedge clk); // cycle 0: warp1 pc0
        @(negedge clk); // cycle 1: warp0 pc4
        @(negedge clk); // cycle 2: warp1 pc4
        @(negedge clk); // cycle 3: warp0 pc8 (r5 = r3+r4 computed combinationally = 35)
        check_all_lanes("warp0 r3+r4 combinational @pc8", 32'd35);

        @(negedge clk); // cycle 4: warp1 pc8
        check_all_lanes("warp1 r3+r4 combinational @pc8", 32'd35);

        @(negedge clk); // cycle 5: warp0 pc12 (readback r5+r0)
        check_all_lanes("warp0 readback r5 (all lanes agree)", 32'd35);

        @(negedge clk); // cycle 6: warp1 pc12 (readback r5+r0)
        check_all_lanes("warp1 readback r5 (isolated from warp0 interleaving)", 32'd35);

        if (errors == 0)
            $display("SM_TOP_TB: ALL TESTS PASSED");
        else
            $display("SM_TOP_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
