//One SIMT lane: register_file.v + alu.v wired together.
// operand read -> ALU compute -> gated writeback
// operand_b_sel: 0 = use rs2 register value (R-type)
//                1 = use sign-extended immediate (I-type)
// active_mask:   1 = lane executes this instruction and may write back

module lane (
    input wire clk,
    input wire rst_n,
    input wire warp_select,   // selects warp's partition in register_file.v

    input wire [3:0] rs1_addr,
    input wire [3:0] rs2_addr,
    input wire [3:0] rd_addr,
    input wire [3:0] alu_opcode,
    input wire operand_b_sel,
    input wire [11:0] immediate,
    input wire active_mask,

    output wire [31:0] alu_result,
    output wire zero
);

    wire [31:0] rs1_data, rs2_data;
    wire [31:0] imm_sext = {{20{immediate[11]}}, immediate}; // sign-extend 12->32
    wire [31:0] operand_b = operand_b_sel ? imm_sext : rs2_data;
    wire write_enable = active_mask;

    register_file u_regfile (
        .clk(clk),
        .rst_n(rst_n),
        .warp_select(warp_select),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .rd_addr(rd_addr),
        .rd_data(alu_result),
        .write_enable(write_enable)
    );

    alu u_alu (
        .opcode(alu_opcode),
        .operand_a(rs1_data),
        .operand_b(operand_b),
        .result(alu_result),
        .zero(zero)
    );

endmodule
