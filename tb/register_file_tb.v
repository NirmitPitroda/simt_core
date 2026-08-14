// =============================================================
// register_file_tb.v
// Covers: reset behavior, gated write, read-after-write, dual-port
// read, r0 hardwired zero (per warp), and WARP ISOLATION — the
// key property that motivated widening this to 32 entries: warp0
// and warp1 writes to the "same" register number must not collide.
// =============================================================

`timescale 1ns/1ps

module register_file_tb;

    reg         clk, rst_n;
    reg         warp_select;
    reg  [3:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    reg         write_enable;
    wire [31:0] rs1_data, rs2_data;

    integer errors;

    register_file dut (
        .clk(clk), .rst_n(rst_n), .warp_select(warp_select),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .write_enable(write_enable)
    );

    always #5 clk = ~clk;

    task check_read;
        input [127:0] name;
        input [31:0]  exp_rs1;
        input [31:0]  exp_rs2;
        begin
            #1;
            if (rs1_data !== exp_rs1) begin
                errors = errors + 1;
                $display("FAIL [%0s]: rs1 expected=%0d got=%0d", name, exp_rs1, rs1_data);
            end
            if (rs2_data !== exp_rs2) begin
                errors = errors + 1;
                $display("FAIL [%0s]: rs2 expected=%0d got=%0d", name, exp_rs2, rs2_data);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; rst_n = 0; warp_select = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; rd_data = 0; write_enable = 0;

        @(negedge clk);
        @(negedge clk);
        rst_n = 1;

        // Write 0xDEADBEEF into WARP0's r5
        @(negedge clk);
        warp_select = 0; rd_addr = 4'd5; rd_data = 32'hDEADBEEF; write_enable = 1;
        @(negedge clk);
        write_enable = 0;
        rs1_addr = 4'd5; rs2_addr = 4'd0;
        check_read("warp0 read-after-write r5", 32'hDEADBEEF, 32'd0);

        // write_enable low -> should NOT write warp0's r6
        rd_addr = 4'd6; rd_data = 32'hCAFECAFE; write_enable = 0;
        @(negedge clk);
        rs1_addr = 4'd6;
        check_read("write_enable low blocks write", 32'd0, 32'd0);

        // write_enable high -> now it takes
        rd_addr = 4'd6; rd_data = 32'hCAFECAFE; write_enable = 1;
        @(negedge clk);
        write_enable = 0;
        rs1_addr = 4'd6;
        check_read("write_enable high allows write", 32'hCAFECAFE, 32'd0);

        // simultaneous dual-port read within warp0
        rs1_addr = 4'd5; rs2_addr = 4'd6;
        check_read("simultaneous dual read (warp0)", 32'hDEADBEEF, 32'hCAFECAFE);

        // r0 hardwired zero on warp0 even if "written"
        rd_addr = 4'd0; rd_data = 32'hFFFFFFFF; write_enable = 1;
        @(negedge clk);
        write_enable = 0;
        rs1_addr = 4'd0; rs2_addr = 4'd0;
        check_read("warp0 r0 hardwired zero", 32'd0, 32'd0);

        // ---- WARP ISOLATION: switch to warp1, r5 should be untouched (0) ----
        warp_select = 1;
        rs1_addr = 4'd5; rs2_addr = 4'd6;
        check_read("warp1 r5/r6 unaffected by warp0 writes", 32'd0, 32'd0);

        // Write a DIFFERENT value into warp1's r5
        rd_addr = 4'd5; rd_data = 32'h11112222; write_enable = 1;
        @(negedge clk);
        write_enable = 0;
        rs1_addr = 4'd5;
        check_read("warp1 r5 write takes its own value", 32'h11112222, 32'd0);

        // Switch back to warp0 -> its r5 must still be the ORIGINAL value,
        // proving warp1's write did not clobber warp0's partition
        warp_select = 0;
        rs1_addr = 4'd5; rs2_addr = 4'd0;
        check_read("warp0 r5 unaffected by warp1 write (isolation)", 32'hDEADBEEF, 32'd0);

        // Reset clears both warps' registers
        rst_n = 0;
        @(negedge clk);
        rst_n = 1;
        warp_select = 0; rs1_addr = 4'd5;
        check_read("reset clears warp0 regs", 32'd0, 32'd0);
        warp_select = 1; rs1_addr = 4'd5;
        check_read("reset clears warp1 regs", 32'd0, 32'd0);

        if (errors == 0)
            $display("REGISTER_FILE_TB: ALL TESTS PASSED");
        else
            $display("REGISTER_FILE_TB: %0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
