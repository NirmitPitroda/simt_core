// =============================================================
// warp_scheduler.v
// Round-robin arbiter between 2 warps. Toggles warp_select every
// cycle. No stall input yet (added later once a warp can actually
// stall on a divergent branch / memory op) — for now this assumes
// a warp is always ready to be fetched on its turn.
// =============================================================

module warp_scheduler (
    input  wire clk,
    input  wire rst_n,
    output reg  warp_select   // 0 = warp0's turn, 1 = warp1's turn
);

    always @(posedge clk) begin
        if (!rst_n)
            warp_select <= 1'b0;
        else
            warp_select <= ~warp_select;
    end

endmodule
