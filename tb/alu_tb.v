// =============================================================
// alu_tb.v
// Directed testbench for alu.v — exercises every opcode plus
// signed-edge cases for SRA/SLT, and the zero-flag path.
// =============================================================

`timescale 1ns/1ps

module alu_tb;

    reg  [3:0]  opcode;
    reg  [31:0] operand_a, operand_b;
    wire [31:0] result;
    wire        zero;

    integer errors;

    alu dut (
        .opcode(opcode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .zero(zero)
    );

    // Checks result and zero flag together, reports mismatches.
    task check;
        input [127:0] name;
        input [31:0]  expected_result;
        begin
            #1;
            if (result !== expected_result) begin
                errors = errors + 1;
                $display("FAIL [%0s]: opcode=%b a=%0d b=%0d expected=%0d got=%0d",
                          name, opcode, operand_a, operand_b, expected_result, result);
            end
            if (zero !== (expected_result == 32'd0)) begin
                errors = errors + 1;
                $display("FAIL [%0s]: zero flag wrong. expected=%0d got=%0d",
                          name, (expected_result == 32'd0), zero);
            end
        end
    endtask

    initial begin
        errors = 0;

        // ADD
        opcode = 4'b0000; operand_a = 32'd10; operand_b = 32'd15;
        check("ADD basic", 32'd25);

        opcode = 4'b0000; operand_a = 32'hFFFFFFFF; operand_b = 32'd1; // overflow wrap
        check("ADD overflow wrap", 32'd0);

        // SUB
        opcode = 4'b0001; operand_a = 32'd20; operand_b = 32'd20;
        check("SUB to zero", 32'd0);

        opcode = 4'b0001; operand_a = 32'd5; operand_b = 32'd10;
        check("SUB negative result", -32'd5);

        // AND
        opcode = 4'b0010; operand_a = 32'hFF00FF00; operand_b = 32'h0F0F0F0F;
        check("AND", 32'h0F000F00);

        // OR
        opcode = 4'b0011; operand_a = 32'hF0F0F0F0; operand_b = 32'h0F0F0F0F;
        check("OR", 32'hFFFFFFFF);

        // XOR
        opcode = 4'b0100; operand_a = 32'hAAAAAAAA; operand_b = 32'hFFFFFFFF;
        check("XOR", 32'h55555555);

        // SLL
        opcode = 4'b0101; operand_a = 32'h00000001; operand_b = 32'd4;
        check("SLL", 32'h00000010);

        // SRL (logical, zero-fill, even for negative-looking pattern)
        opcode = 4'b0110; operand_a = 32'h80000000; operand_b = 32'd4;
        check("SRL zero-fill", 32'h08000000);

        // SRA (arithmetic, sign-extend)
        opcode = 4'b0111; operand_a = 32'h80000000; operand_b = 32'd4; // negative number
        check("SRA sign-extend", 32'hF8000000);

        opcode = 4'b0111; operand_a = 32'h00000010; operand_b = 32'd2; // positive number
        check("SRA positive", 32'h00000004);

        // SLT signed
        opcode = 4'b1000; operand_a = -32'd5; operand_b = 32'd3; // -5 < 3
        check("SLT signed true (negative vs positive)", 32'd1);

        opcode = 4'b1000; operand_a = 32'd3; operand_b = -32'd5; // 3 < -5 false
        check("SLT signed false", 32'd0);

        opcode = 4'b1000; operand_a = 32'd7; operand_b = 32'd7; // equal -> not less
        check("SLT equal", 32'd0);

        // default / undefined opcode -> result forced to 0
        opcode = 4'b1111; operand_a = 32'd99; operand_b = 32'd1;
        check("undefined opcode default", 32'd0);

        if (errors == 0)
            $display("ALU_TB: ALL TESTS PASSED");
        else
            $display("ALU_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
