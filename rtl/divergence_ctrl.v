// =============================================================
// divergence_ctrl.v
// Per-warp active-mask tracking + predicate (reconvergence) stack.
//
// IMPORTANT — why this is mask-only, with no PC redirection:
// fetch_unit.v has exactly one PC per warp (pc0/pc1), not one per
// lane. A warp's 4 lanes always fetch the SAME instruction stream
// in program order. There is also no unconditional-jump instruction
// in this ISA (decode_unit.v only has R/I/BRANCH/LOAD/STORE) — so a
// compiled if/else can never route the "skip" path around the
// "fall-through" block via a jump; the ISA can only express
// structured forward "skip-if-true" branches:
//
//   is_branch: compare rs1 vs rs2 (via alu_opcode, e.g. SUB) per
//   lane. cond[i] = 1 (that lane's ALU zero flag) means lane i's
//   condition is TRUE -> that thread SKIPS the block between this
//   instruction and branch_target (current_pc + sext(immediate)).
//   cond[i] = 0 means that thread falls through and executes the
//   block, then rejoins at branch_target.
//
// Since every lane's PC is the same warp-shared PC regardless, the
// front end always marches through every instruction in program
// order — "skip" is therefore implemented purely by deactivating
// (masking) the skipping lanes for that instruction range, not by
// actually redirecting fetch. This is why branch_taken/branch_target
// to fetch_unit are left tied off below: real PC redirection isn't
// meaningful (or needed) for divergence in this ISA. Those ports
// are kept wired for interface completeness, e.g. if a future
// unconditional-jump instruction is added.
//
// Divergence handling:
//   taken_mask     = active_mask & cond          (lanes that skip)
//   not_taken_mask = active_mask & ~cond          (lanes that execute the block)
//
//   If taken_mask != 0: push {pc = branch_target, mask = taken_mask}
//   onto this warp's stack (to be reactivated once the block is
//   passed) and set active_mask <= not_taken_mask for the block.
//   (If not_taken_mask happens to be 0 too — i.e. every active lane
//   skips — the block's instructions simply execute with an
//   all-zero mask; harmless, just no register writes occur.)
//
// Reconvergence:
//   Every cycle, current_pc is checked against the top of that
//   warp's stack. On a match, the entry is popped and its mask is
//   OR'd back into the warp's active_mask, reactivating the lanes
//   that had skipped ahead. This also handles nested divergence
//   (nested branches just push additional entries, unwound LIFO).
// =============================================================

module divergence_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        fetched_warp,   // from fetch_unit: which warp this cycle's instruction belongs to
    input  wire [31:0] current_pc,     // from fetch_unit: PC of the instruction just fetched
    input  wire         is_branch,      // from decode_unit
    input  wire [11:0] immediate,      // from decode_unit: branch offset

    input  wire        lane0_zero,     // from lane[i].alu: per-lane branch-condition result
    input  wire        lane1_zero,
    input  wire        lane2_zero,
    input  wire        lane3_zero,

    output wire [3:0]  active_mask,    // active_mask for the currently fetched warp -> fans out to lane0..3

    // Kept for interface completeness / future extension (e.g. an
    // unconditional-jump instruction). Not needed for correctness
    // of divergence with this ISA — see header comment — so these
    // are tied off.
    output wire         branch_taken,
    output wire [31:0] branch_target,
    output wire         branch_warp
);

    localparam STACK_DEPTH = 8;

    assign branch_taken  = 1'b0;
    assign branch_target = 32'd0;
    assign branch_warp   = 1'b0;

    // ---------------- Per-warp active mask ----------------
    reg [3:0] mask0, mask1;

    assign active_mask = fetched_warp ? mask1 : mask0;

    // ---------------- Per-warp predicate (reconvergence) stacks ----------------
    reg [31:0] stack_pc0   [0:STACK_DEPTH-1];
    reg [3:0]  stack_mask0 [0:STACK_DEPTH-1];
    reg [3:0]  sp0;                              // number of live entries

    reg [31:0] stack_pc1   [0:STACK_DEPTH-1];
    reg [3:0]  stack_mask1 [0:STACK_DEPTH-1];
    reg [3:0]  sp1;

    // ---------------- Branch condition / target (combinational) ----------------
    wire [3:0]  cond      = {lane3_zero, lane2_zero, lane1_zero, lane0_zero};
    wire [31:0] imm_sext  = {{20{immediate[11]}}, immediate};
    wire [31:0] target_pc = current_pc + imm_sext;

    wire [3:0] taken_mask0     = mask0 & cond;
    wire [3:0] not_taken_mask0 = mask0 & ~cond;

    wire [3:0] taken_mask1     = mask1 & cond;
    wire [3:0] not_taken_mask1 = mask1 & ~cond;

    wire reconverge0 = (sp0 != 0) && (current_pc == stack_pc0[sp0-1]);
    wire reconverge1 = (sp1 != 0) && (current_pc == stack_pc1[sp1-1]);

    always @(posedge clk) begin
        if (!rst_n) begin
            mask0 <= 4'b1111;
            mask1 <= 4'b1111;
            sp0   <= 4'd0;
            sp1   <= 4'd0;
        end else begin
            if (fetched_warp == 1'b0) begin
                if (reconverge0) begin
                    mask0 <= mask0 | stack_mask0[sp0-1];
                    sp0   <= sp0 - 4'd1;
                end else if (is_branch && (taken_mask0 != 4'b0000)) begin
                    if (sp0 < STACK_DEPTH) begin
                        stack_pc0[sp0]   <= target_pc;
                        stack_mask0[sp0] <= taken_mask0;
                        sp0              <= sp0 + 4'd1;
                    end else begin
                        // synthesis translate_off
                        $display("divergence_ctrl: warp0 stack overflow at pc=%0d, push dropped", current_pc);
                        // synthesis translate_on
                    end
                    mask0 <= not_taken_mask0;
                end
            end else begin
                if (reconverge1) begin
                    mask1 <= mask1 | stack_mask1[sp1-1];
                    sp1   <= sp1 - 4'd1;
                end else if (is_branch && (taken_mask1 != 4'b0000)) begin
                    if (sp1 < STACK_DEPTH) begin
                        stack_pc1[sp1]   <= target_pc;
                        stack_mask1[sp1] <= taken_mask1;
                        sp1              <= sp1 + 4'd1;
                    end else begin
                        // synthesis translate_off
                        $display("divergence_ctrl: warp1 stack overflow at pc=%0d, push dropped", current_pc);
                        // synthesis translate_on
                    end
                    mask1 <= not_taken_mask1;
                end
            end
        end
    end

endmodule
