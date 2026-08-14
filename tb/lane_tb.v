// =============================================================
// lane_tb.v
// Integration testbench for lane.v (register_file.v + alu.v).
// Covers: R-type op, I-type immediate op, active_mask=0 blocking
// writeback, and chaining (writeback of one op feeds next op's
// operand read).
// =============================================================

`timescale 1ns/1ps

module lane_tb;

    reg         clk, rst_n;
    reg  [3:0]  rs1_addr, rs2_addr, rd_addr, alu_opcode;
    reg         operand_b_sel;
    reg  [11:0] immediate;
    reg         active_mask;
    reg         warp_select;
    wire [31:0] alu_result;
    wire        zero;

    integer errors;

    lane dut (
        .clk(clk), .rst_n(rst_n),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .operand_b_sel(operand_b_sel),
        .immediate(immediate), .active_mask(active_mask), .warp_select(warp_select),
        .alu_result(alu_result), .zero(zero)
    );

    always #5 clk = ~clk;

    task check_result;
        input [127:0] name;
        input [31:0]  expected;
        begin
            #1;
            if (alu_result !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0s]: expected=%0d got=%0d", name, expected, alu_result);
            end
        end
    endtask

    // Preload a register via a "setup" write cycle: an ADD with rs1=0(=0),
    // immediate = value, rd = target reg, mask=1.
    task load_reg;
        input [3:0]  reg_num;
        input [31:0] value;
        begin
            rs1_addr = 4'd0;          // r0 = 0
            operand_b_sel = 1'b1;     // immediate path
            immediate = value[11:0];  // fits our test values
            alu_opcode = 4'b0000;     // ADD -> result = 0 + imm
            rd_addr = reg_num;
            active_mask = 1'b1;
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; rst_n = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; alu_opcode = 0;
        operand_b_sel = 0; immediate = 0; active_mask = 0; warp_select = 0;

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;

        // Load r3 = 10, r4 = 25 via immediate-ADD writes
        load_reg(4'd3, 32'd10);
        load_reg(4'd4, 32'd25);

        // R-type: r5 = r3 + r4  (rs1=3, rs2=4, ADD, operand_b_sel=0)
        rs1_addr = 4'd3; rs2_addr = 4'd4; rd_addr = 4'd5;
        alu_opcode = 4'b0000; operand_b_sel = 1'b0; active_mask = 1'b1;
        check_result("R-type ADD combinational (pre-writeback)", 32'd35);
        @(negedge clk); // commit writeback of r5 = 35

        // Chaining: r6 = r5 - r3  (uses the value just written back)
        rs1_addr = 4'd5; rs2_addr = 4'd3; rd_addr = 4'd6;
        alu_opcode = 4'b0001; operand_b_sel = 1'b0; active_mask = 1'b1;
        check_result("chained read-after-write (35-10)", 32'd25);
        @(negedge clk); // commit writeback of r6 = 25

        // active_mask = 0: attempt to overwrite r6 with garbage, should NOT take
        rs1_addr = 4'd0; rs2_addr = 4'd0; rd_addr = 4'd6;
        alu_opcode = 4'b0000; operand_b_sel = 1'b1; immediate = 12'd999;
        active_mask = 1'b0; // masked off
        @(negedge clk);
        // now read r6 back out to confirm it is still 25
        rs1_addr = 4'd6; rs2_addr = 4'd0; alu_opcode = 4'b0000;
        operand_b_sel = 1'b0; active_mask = 1'b0; // read-only, no write
        check_result("masked lane did not write back", 32'd25);

        if (errors == 0)
            $display("LANE_TB: ALL TESTS PASSED");
        else
            $display("LANE_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
