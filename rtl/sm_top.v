// warp_scheduler -> fetch_unit -> decode_unit -> divergence_ctrl -> 4x lane
//
// All 4 lanes receive the SAME decoded instruction (same rs1/rs2/rd
// register *numbers*, same opcode) but each has its own private
// register_file.v (per lane.v), which is the core SIMT idea: one
// instruction stream, per-thread register state.
//
// divergence_ctrl.v tracks a separate active_mask + reconvergence
// stack per warp and drives per-lane active_mask, plus
// branch_taken/branch_target/branch_warp back into fetch_unit for
// PC redirection on taken branches.

module sm_top (
    input wire clk,
    input wire rst_n,

    // Debug/observation outputs (useful for testbenches and the
    // golden-model diff later) — result + zero flag from each lane.
    output wire [31:0] lane0_result, lane1_result, lane2_result, lane3_result,
    output wire lane0_zero,   lane1_zero,   lane2_zero,   lane3_zero,
    output wire [31:0] debug_pc,
    output wire debug_warp_select,
    output wire [3:0] debug_active_mask
);

    // ---------------- Warp scheduler ----------------
    wire warp_select;

    warp_scheduler u_warp_sched (
        .clk(clk), .rst_n(rst_n),
        .warp_select(warp_select)
    );

    // ---------------- Fetch ----------------
    wire [31:0] instruction;
    wire [31:0] current_pc;
    wire fetched_warp;

    wire branch_taken;
    wire [31:0] branch_target;
    wire branch_warp;

    fetch_unit u_fetch (
        .clk(clk), .rst_n(rst_n),
        .warp_select(warp_select),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .branch_warp(branch_warp),
        .instruction(instruction),
        .current_pc(current_pc),
        .fetched_warp(fetched_warp)
    );

    assign debug_pc = current_pc;
    assign debug_warp_select = fetched_warp;

    // ---------------- Decode ----------------
    wire [3:0]  rs1_addr, rs2_addr, rd_addr, alu_opcode;
    wire [11:0] immediate;
    wire operand_b_sel;
    wire [3:0]  itype;
    wire is_rtype, is_itype, is_branch, is_load, is_store;

    decode_unit u_decode (
        .instruction(instruction),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .immediate(immediate),
        .operand_b_sel(operand_b_sel), .itype(itype),
        .is_rtype(is_rtype), .is_itype(is_itype), .is_branch(is_branch),
        .is_load(is_load), .is_store(is_store)
    );

    // ---------------- Divergence control ----------------
    wire [3:0] active_mask;

    divergence_ctrl u_divergence (
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

    assign debug_active_mask = active_mask;

    // ---------------- 4 lanes (SIMT width) ----------------
    lane u_lane0 (
        .clk(clk), .rst_n(rst_n), .warp_select(fetched_warp),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .operand_b_sel(operand_b_sel), .immediate(immediate),
        .active_mask(active_mask[0]),
        .alu_result(lane0_result), .zero(lane0_zero)
    );

    lane u_lane1 (
        .clk(clk), .rst_n(rst_n), .warp_select(fetched_warp),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .operand_b_sel(operand_b_sel), .immediate(immediate),
        .active_mask(active_mask[1]),
        .alu_result(lane1_result), .zero(lane1_zero)
    );

    lane u_lane2 (
        .clk(clk), .rst_n(rst_n), .warp_select(fetched_warp),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .operand_b_sel(operand_b_sel), .immediate(immediate),
        .active_mask(active_mask[2]),
        .alu_result(lane2_result), .zero(lane2_zero)
    );

    lane u_lane3 (
        .clk(clk), .rst_n(rst_n), .warp_select(fetched_warp),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_opcode(alu_opcode), .operand_b_sel(operand_b_sel), .immediate(immediate),
        .active_mask(active_mask[3]),
        .alu_result(lane3_result), .zero(lane3_zero)
    );

endmodule
