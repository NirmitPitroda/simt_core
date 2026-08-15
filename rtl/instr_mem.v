// Simple word-addressable instruction memory. Async (combinational)
// read to match register_file.v's convention. Depth = 256 words.

module instr_mem (
    input wire [31:0] addr,   // byte address; word-aligned (addr[1:0] ignored)
    output wire [31:0] rdata
);
    reg [31:0] mem [0:255];
    assign rdata = mem[addr[9:2]]; // 256 words -> 8-bit index, /4 for word align
endmodule
