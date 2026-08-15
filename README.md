# Simplified Streaming Multiprocessor (SM) — RTL

A simplified GPU Streaming Multiprocessor implemented in Verilog, built to explore
core SIMT microarchitecture concepts: warp scheduling, execution masks, and
divergence/reconvergence via a predicate stack.

## Architecture

- **4-lane SIMT datapath, 2 warps**
- **32-bit datapath**, RISC-V-inspired fixed-field instruction format
- **16 registers/thread**, warp-partitioned register file (32 entries: 2 warps × 16 regs)
- **Round-robin warp scheduler**
- **Divergence handling**: per-lane execution masks + IPDOM (immediate post-dominator)
  reconvergence stack, one stack per warp, 3-entry-push algorithm on divergent branches

```
sm_top.v
├── warp_scheduler.v      (round-robin arbitration between 2 warps)
├── fetch_unit.v          (per-warp PC, instruction fetch)
│   └── instr_mem.v
├── decode_unit.v         (instruction field extraction)
├── divergence_ctrl.v     (per-warp reconvergence stack, mask generation)
└── lane.v  ×4             (one SIMT lane)
    ├── register_file.v   (warp-partitioned, 32 entries)
    └── alu.v              (9-op combinational ALU)
```

## Instruction format (32-bit)

```
[31:28] rs2      (4b)
[27:24] rs1      (4b)
[23:20] rd       (4b)
[19:16] funct    (4b)  -- ALU opcode / branch condition code
[15:12] itype    (4b)  -- 0000=R-type 0001=I-type 0010=BRANCH 0011=LOAD 0100=STORE
[11:0]  imm      (12b) -- used by I-type / BRANCH / LOAD / STORE
```

## Divergence handling — design notes

`divergence_ctrl.v` implements the classic IPDOM reconvergence stack (as described in
Aamodt, Fung & Rogers, *General-Purpose Graphics Processor Architectures*, §3.1.3— the
same mechanism used in early GPGPU-Sim models). On a divergent branch it pops the
current stack entry and pushes three: a RECONV entry (parked with the full pre-branch
mask), a not-taken entry (executes the fallthrough body), and a taken entry (jumps to
target) on top. Each diverged path independently runs until its PC reaches the
reconvergence PC, at which point it retires itself in a 1-cycle bubble (no lane
writes). Once both paths have retired, the RECONV entry surfaces with the full mask
and execution proceeds reunited. This handles **nested divergence** correctly (verified
in `divergence_ctrl_tb.v`).

### Known, documented limitation

**Reconvergence PC = the branch's own target address.** This is correct for
structured `if (cond) { body }` code, where the branch skips forward over a body and
both paths land on the same post-branch address. It does **not** generally solve
reconvergence for divergent loops or unstructured control flow — real GPU ISAs
historically solved this with compiler-inserted reconvergence markers (e.g. SSY/SYNC
on pre-Volta NVIDIA hardware) rather than deriving it dynamically. This is a
deliberate scoping decision for this project, not an oversight.

## Verification

Every module has a directed testbench (`tb/*_tb.v`), run with Icarus Verilog
(`iverilog`/`vvp`). All testbenches pass, including:
- Per-module isolation tests (ALU op coverage, register file warp-isolation,
  decode field extraction, fetch PC sequencing)
- `divergence_ctrl_tb.v`: uniform branches (taken/not-taken), a single divergent
  branch with correct mask split and reconvergence, and **nested divergence**
  (divergent branch inside a divergent branch) with correct inner/outer reconvergence
- `sm_top_tb.v`: full pipeline integration, straight-line execution across both
  interleaved warps with verified register-file isolation

## Toolchain

Verilog + Vivado (synthesis/simulation)
