// =============================================================
// fetch_unit_tb.v
// Covers: independent per-warp PC sequencing (each warp's PC only
// advances on cycles it's selected), correct instruction fetched
// per PC, and branch redirect overriding the named warp's PC.
// =============================================================

`timescale 1ns/1ps

module fetch_unit_tb;

    reg         clk, rst_n;
    reg         warp_select;
    reg         branch_taken;
    reg  [31:0] branch_target;
    reg         branch_warp;
    wire [31:0] instruction, current_pc;
    wire        fetched_warp;

    integer errors;

    fetch_unit dut (
        .clk(clk), .rst_n(rst_n),
        .warp_select(warp_select),
        .branch_taken(branch_taken), .branch_target(branch_target), .branch_warp(branch_warp),
        .instruction(instruction), .current_pc(current_pc), .fetched_warp(fetched_warp)
    );

    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input [31:0]  exp_pc;
        input [31:0]  exp_instr;
        begin
            #1;
            if (current_pc !== exp_pc) begin
                errors = errors + 1;
                $display("FAIL [%0s]: pc expected=%0d got=%0d", name, exp_pc, current_pc);
            end
            if (instruction !== exp_instr) begin
                errors = errors + 1;
                $display("FAIL [%0s]: instr expected=%h got=%h", name, exp_instr, instruction);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; rst_n = 0;
        warp_select = 0; branch_taken = 0; branch_target = 0; branch_warp = 0;

        // Preload instruction memory: distinct markers at word indices 0-5
        dut.u_imem.mem[0] = 32'hAAAA0000; // warp0 pc=0
        dut.u_imem.mem[1] = 32'hAAAA0004; // warp0 pc=4
        dut.u_imem.mem[2] = 32'hAAAA0008; // warp0 pc=8
        dut.u_imem.mem[0+64] = 32'hBBBB0000; // just filler, unused
        // warp1 reuses same memory since single shared imem; word idx = pc/4
        // (already covered by mem[0..2] since both warps share the same memory)

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;

        // Cycle 1: fetch warp0 @ pc=0
        warp_select = 0;
        check("warp0 fetch #1 (pc=0)", 32'd0, 32'hAAAA0000);
        @(negedge clk); // pc0 -> 4

        // Cycle 2: fetch warp1 @ pc=0 (warp1 hasn't advanced yet, still 0)
        warp_select = 1;
        check("warp1 fetch #1 (pc=0, independent of warp0)", 32'd0, 32'hAAAA0000);
        @(negedge clk); // pc1 -> 4

        // Cycle 3: fetch warp0 again @ pc=4 (advanced only on its own turn)
        warp_select = 0;
        check("warp0 fetch #2 (pc=4)", 32'd4, 32'hAAAA0004);
        @(negedge clk); // pc0 -> 8

        // Cycle 4: fetch warp1 again @ pc=4
        warp_select = 1;
        check("warp1 fetch #2 (pc=4)", 32'd4, 32'hAAAA0004);
        @(negedge clk); // pc1 -> 8

        // Branch redirect: force warp0's PC to 8*... let's redirect to word idx 2 (pc=8) already there,
        // instead redirect warp1 to pc=8 explicitly to prove branch override works independent of warp0
        warp_select = 1;
        branch_taken = 1; branch_target = 32'd8; branch_warp = 1'b1; // redirect warp1
        @(negedge clk); // pc1 <= 8 (branch overrides the normal +4 to what would've been 12)
        branch_taken = 0;

        warp_select = 1;
        check("warp1 branch redirect took effect (pc=8)", 32'd8, 32'hAAAA0008);
        @(negedge clk);

        // Confirm warp0's PC was unaffected by warp1's branch (still at 8 from cycle 4's +4)
        warp_select = 0;
        check("warp0 PC unaffected by warp1 branch (pc=8)", 32'd8, 32'hAAAA0008);

        if (errors == 0)
            $display("FETCH_UNIT_TB: ALL TESTS PASSED");
        else
            $display("FETCH_UNIT_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
