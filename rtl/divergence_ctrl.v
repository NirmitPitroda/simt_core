module divergence_ctrl(
    input wire clk,
    input wire rst_n,

    input wire fetched_warp,      // from fetch_unit: which warp this cycle's instruction belongs to
    input wire [31:0] current_pc, // from fetch_unit: PC of the instruction just fetched
    input wire is_branch,         // from decode_unit
    input wire [11:0] immediate,  // from decode_unit: branch offset

    input wire lane0_zero,     // from lane[i].alu: per-lane branch-condition result
    input wire lane1_zero,
    input wire lane2_zero,
    input wire lane3_zero,

    output wire [3:0] active_mask,    // active_mask for the currently fetched warp -> fans out to lane0..3

    // Kept for interface completeness / future extension (e.g. an
    // unconditional-jump instruction). Not needed for correctness
    // of divergence with this ISA — see header comment — so these
    // are tied off.
    output wire branch_taken,
    output wire [31:0] branch_target,
    output wire branch_warp
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
    wire [3:0] cond = {lane3_zero, lane2_zero, lane1_zero, lane0_zero};
    wire [31:0] imm_sext = {{20{immediate[11]}}, immediate};
    wire [31:0] target_pc = current_pc + imm_sext;

    wire [3:0] taken_mask0 = mask0 & cond;
    wire [3:0] not_taken_mask0 = mask0 & ~cond;

    wire [3:0] taken_mask1 = mask1 & cond;
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
