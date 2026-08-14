// =============================================================
// decode_unit.v
// Decodes a 32-bit instruction into the control signals lane.v
// (and, later, fetch_unit.v / divergence_ctrl.v) consume.
//
// Instruction layout (32b, RISC-V-inspired, simplified):
//   [31:28] rs2
//   [27:24] rs1
//   [23:20] rd
//   [19:16] funct     (ALU opcode / branch condition code)
//   [15:12] itype
//   [11:0]  imm        (used by I-type / BRANCH / LOAD / STORE)
//
// itype encoding:
//   0000 = R-type   (ALU reg-reg;      operand_b = rs2)
//   0001 = I-type   (ALU reg-imm;      operand_b = sext(imm))
//   0010 = BRANCH   (compare rs1,rs2;  operand_b = rs2, imm=offset)
//   0011 = LOAD     (addr = rs1+imm;   operand_b = sext(imm))
//   0100 = STORE    (addr = rs1+imm;   operand_b = sext(imm))
// =============================================================

module decode_unit (
    input  wire [31:0] instruction,

    output wire [3:0]  rs1_addr,
    output wire [3:0]  rs2_addr,
    output wire [3:0]  rd_addr,
    output wire [3:0]  alu_opcode,
    output wire [11:0] immediate,
    output wire        operand_b_sel,   // 0 = use rs2, 1 = use immediate

    output wire [3:0]  itype,
    output wire        is_rtype,
    output wire        is_itype,
    output wire        is_branch,
    output wire        is_load,
    output wire        is_store
);

    localparam ITYPE_R      = 4'b0000;
    localparam ITYPE_I      = 4'b0001;
    localparam ITYPE_BRANCH = 4'b0010;
    localparam ITYPE_LOAD   = 4'b0011;
    localparam ITYPE_STORE  = 4'b0100;

    assign rs2_addr   = instruction[31:28];
    assign rs1_addr   = instruction[27:24];
    assign rd_addr    = instruction[23:20];
    assign alu_opcode = instruction[19:16];
    assign itype      = instruction[15:12];
    assign immediate  = instruction[11:0];

    assign is_rtype  = (itype == ITYPE_R);
    assign is_itype  = (itype == ITYPE_I);
    assign is_branch = (itype == ITYPE_BRANCH);
    assign is_load   = (itype == ITYPE_LOAD);
    assign is_store  = (itype == ITYPE_STORE);

    // R-type and BRANCH both need two register operands (branch
    // compares rs1 vs rs2). Everything else (I-type/LOAD/STORE)
    // uses the sign-extended immediate as operand_b.
    assign operand_b_sel = ~(is_rtype | is_branch);

endmodule
