// =============================================================
// decode_unit_tb.v
// Verifies field extraction and type-flag/operand_b_sel logic
// for all 5 instruction types.
// =============================================================

`timescale 1ns/1ps

module decode_unit_tb;

    reg  [31:0] instruction;

    wire [3:0]  rs1_addr, rs2_addr, rd_addr, alu_opcode, itype;
    wire [11:0] immediate;
    wire        operand_b_sel;
    wire        is_rtype, is_itype, is_branch, is_load, is_store;

    integer errors;

    decode_unit dut (
        .instruction(instruction),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .immediate(immediate),
        .operand_b_sel(operand_b_sel), .itype(itype),
        .is_rtype(is_rtype), .is_itype(is_itype), .is_branch(is_branch),
        .is_load(is_load), .is_store(is_store)
    );

    // Builds an instruction word from fields, per the ISA layout.
    function [31:0] build_instr;
        input [3:0]  rs2, rs1, rd, funct, itype_f;
        input [11:0] imm;
        begin
            build_instr = {rs2, rs1, rd, funct, itype_f, imm};
        end
    endfunction

    task check;
        input [127:0] name;
        input [3:0]  exp_rs1, exp_rs2, exp_rd, exp_funct;
        input [11:0] exp_imm;
        input        exp_bsel;
        input        exp_r, exp_i, exp_br, exp_ld, exp_st;
        begin
            #1;
            if (rs1_addr !== exp_rs1)   begin errors=errors+1; $display("FAIL[%0s] rs1_addr exp=%b got=%b", name, exp_rs1, rs1_addr); end
            if (rs2_addr !== exp_rs2)   begin errors=errors+1; $display("FAIL[%0s] rs2_addr exp=%b got=%b", name, exp_rs2, rs2_addr); end
            if (rd_addr  !== exp_rd)    begin errors=errors+1; $display("FAIL[%0s] rd_addr exp=%b got=%b", name, exp_rd, rd_addr); end
            if (alu_opcode !== exp_funct) begin errors=errors+1; $display("FAIL[%0s] alu_opcode exp=%b got=%b", name, exp_funct, alu_opcode); end
            if (immediate !== exp_imm)  begin errors=errors+1; $display("FAIL[%0s] immediate exp=%h got=%h", name, exp_imm, immediate); end
            if (operand_b_sel !== exp_bsel) begin errors=errors+1; $display("FAIL[%0s] operand_b_sel exp=%b got=%b", name, exp_bsel, operand_b_sel); end
            if (is_rtype !== exp_r)   begin errors=errors+1; $display("FAIL[%0s] is_rtype exp=%b got=%b", name, exp_r, is_rtype); end
            if (is_itype !== exp_i)   begin errors=errors+1; $display("FAIL[%0s] is_itype exp=%b got=%b", name, exp_i, is_itype); end
            if (is_branch !== exp_br) begin errors=errors+1; $display("FAIL[%0s] is_branch exp=%b got=%b", name, exp_br, is_branch); end
            if (is_load !== exp_ld)   begin errors=errors+1; $display("FAIL[%0s] is_load exp=%b got=%b", name, exp_ld, is_load); end
            if (is_store !== exp_st)  begin errors=errors+1; $display("FAIL[%0s] is_store exp=%b got=%b", name, exp_st, is_store); end
        end
    endtask

    initial begin
        errors = 0;

        // R-type: rs2=4'd3, rs1=4'd2, rd=4'd1, funct=ADD(0000), itype=0000, imm=don't care(0)
        instruction = build_instr(4'd3, 4'd2, 4'd1, 4'b0000, 4'b0000, 12'd0);
        check("R-type ADD", 4'd2, 4'd3, 4'd1, 4'b0000, 12'd0, 1'b0, 1,0,0,0,0);

        // I-type: rs1=4'd5, rd=4'd6, funct=ADD, itype=0001, imm=12'd100
        instruction = build_instr(4'd0, 4'd5, 4'd6, 4'b0000, 4'b0001, 12'd100);
        check("I-type ADDI", 4'd5, 4'd0, 4'd6, 4'b0000, 12'd100, 1'b1, 0,1,0,0,0);

        // BRANCH: rs1=4'd7, rs2=4'd8, funct=SLT(1000) as condition code, itype=0010, imm=offset
        instruction = build_instr(4'd8, 4'd7, 4'd0, 4'b1000, 4'b0010, 12'd20);
        check("BRANCH", 4'd7, 4'd8, 4'd0, 4'b1000, 12'd20, 1'b0, 0,0,1,0,0);

        // LOAD: rs1=4'd9(base), rd=4'd10(dest), itype=0011, imm=offset
        instruction = build_instr(4'd0, 4'd9, 4'd10, 4'b0000, 4'b0011, 12'd8);
        check("LOAD", 4'd9, 4'd0, 4'd10, 4'b0000, 12'd8, 1'b1, 0,0,0,1,0);

        // STORE: rs1=4'd11(base), rs2=4'd12(data), itype=0100, imm=offset
        instruction = build_instr(4'd12, 4'd11, 4'd0, 4'b0000, 4'b0100, 12'd4);
        check("STORE", 4'd11, 4'd12, 4'd0, 4'b0000, 12'd4, 1'b1, 0,0,0,0,1);

        if (errors == 0)
            $display("DECODE_UNIT_TB: ALL TESTS PASSED");
        else
            $display("DECODE_UNIT_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
