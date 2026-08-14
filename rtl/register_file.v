// =============================================================
// register_file.v
// Per-lane register file, now WARP-PARTITIONED: 32 entries total
// = 2 warps x 16 registers/warp. Addressed by {warp_select, addr}.
// This exists because a single lane is shared by both warps as
// the scheduler round-robins between them — without partitioning,
// warp0 and warp1 would clobber each other's register state.
//
// 2 async read ports (rs1, rs2), 1 sync write port gated by
// write_enable (masked-off lanes drive this low).
// r0 is hardwired to zero WITHIN EACH WARP's partition (i.e. both
// warp0's r0 and warp1's r0 read as constant zero).
// =============================================================

module register_file (
    input  wire        clk,
    input  wire        rst_n,        // active-low synchronous reset

    input  wire        warp_select,  // which warp's partition to access

    input  wire [3:0]  rs1_addr,
    input  wire [3:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,

    input  wire [3:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        write_enable  // masked-off lanes drive this low
);

    reg [31:0] regs [0:31]; // index 0-15 = warp0, 16-31 = warp1

    integer i;

    wire [4:0] rs1_full = {warp_select, rs1_addr};
    wire [4:0] rs2_full = {warp_select, rs2_addr};
    wire [4:0] rd_full  = {warp_select, rd_addr};

    // Async (combinational) reads. r0 hardwired to zero per-warp.
    assign rs1_data = (rs1_addr == 4'd0) ? 32'd0 : regs[rs1_full];
    assign rs2_data = (rs2_addr == 4'd0) ? 32'd0 : regs[rs2_full];

    // Synchronous, gated write.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (write_enable && rd_addr != 4'd0) begin
            regs[rd_full] <= rd_data;
        end
    end

endmodule
