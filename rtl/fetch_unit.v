// =============================================================
// fetch_unit.v
// Maintains one PC per warp (2 warps). Each cycle, warp_select
// (driven later by warp_scheduler.v) picks which warp's PC drives
// the instruction memory address. Sequential PC += 4, except when
// branch_taken redirects the named warp's PC to branch_target
// (branch_taken/branch_target/branch_warp will be driven by
// divergence_ctrl.v once branch resolution exists; tie low for now).
// =============================================================

module fetch_unit (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        warp_select,    // 0 or 1: which warp to fetch this cycle

    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    input  wire        branch_warp,    // which warp's PC branch_taken applies to

    output wire [31:0] instruction,
    output wire [31:0] current_pc,     // PC of the instruction just fetched
    output wire        fetched_warp    // echoes warp_select for downstream tagging
);

    reg [31:0] pc0, pc1;
    wire [31:0] selected_pc = warp_select ? pc1 : pc0;

    assign current_pc  = selected_pc;
    assign fetched_warp = warp_select;

    instr_mem u_imem (
        .addr(selected_pc),
        .rdata(instruction)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            pc0 <= 32'd0;
            pc1 <= 32'd0;
        end else begin
            // warp 0 PC update
            if (branch_taken && (branch_warp == 1'b0))
                pc0 <= branch_target;
            else if (warp_select == 1'b0)
                pc0 <= pc0 + 32'd4;

            // warp 1 PC update
            if (branch_taken && (branch_warp == 1'b1))
                pc1 <= branch_target;
            else if (warp_select == 1'b1)
                pc1 <= pc1 + 32'd4;
        end
    end

endmodule
