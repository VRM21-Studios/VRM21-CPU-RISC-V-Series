# 01 Architecture

## Hierarchy

```text
vrm_soc_axi                 AXI4-Lite slave, CPU_CTRL, AXI4-Stream ports
├── vrm_bootloader          copies firmware.mem into RAM, reset trampoline
└── vrm_soc_top             write-port arbitration, 64 KiB RAM, read paths
    ├── vrm_vcf_mmio        VCF registers, commit logic, stream datapath
    │   ├── vrm_vcf_core    left channel (Chamberlin SVF)
    │   └── vrm_vcf_core    right channel
    └── vrm_cpu_rv32im_wrapper
        ├── vrm_cpu_rv32im_core
        │   ├── vrm_alu
        │   ├── vrm_mdu     RV32M multiply/divide
        │   └── vrm_csr     machine-mode CSRs
        ├── vrm_timer       32-bit compare timer (MTIP)
        └── vrm_irq_arbiter edge-triggered interrupt aggregator (MEIP)
```

## CPU Pipeline

The core is a five-stage in-order pipeline:

```text
IF → ID → EX → MEM → WB
```

Instruction fetch reads the RAM combinationally through a dedicated port, so
fetch never competes with data accesses. Decode reads the register file with
write-through of the value being written back. Branches, jumps, and MRET
resolve in EX and flush IF/ID and ID/EX. EX forwards from EX/MEM and MEM/WB; a
CSR instruction in MEM forwards its old CSR value. A load followed by a
dependent instruction, or two dependent CSR instructions, insert one bubble.

Multiply instructions complete one cycle after they start. Division and
remainder run for 32 iterations, during which the pipeline holds the
instruction in EX. Interrupts are not taken while an M-extension instruction
is in EX, MEM, or WB, which bounds the interrupt latency: the FreeRTOS
testbench measured at most 59 cycles from MTIP to trap entry during DIV and
25 cycles during REM.

WFI is drained to retirement without issuing a younger instruction behind it.
After it retires, the core halts until `(mip & mie) != 0`. With the global
interrupt enable set, the pending interrupt is taken and `mepc` points to the
instruction after WFI; with it cleared, the core resumes without a trap.

## SoC Buses

`vrm_soc_top` has one arbitrated RAM write port shared by three requesters,
with priority bootloader, then host, then CPU. Boot and host writes are full
words; CPU writes use the byte enables of SB, SH, and SW. Reads have separate
combinational paths for CPU data, instruction fetch, and host reads, so a host
read never takes the CPU bus.

WARNING: a host write in the same cycle as a CPU store is not retried and the
CPU store is lost. A host that writes RAM or VCF registers while the CPU runs
must hold the CPU first (CPU_CTRL = 0) or ensure that the CPU does not access
data in that window. Host reads are always safe.

The RAM is a 16384 × 32-bit array. The 4 KiB ROM window at `0x0000_0000`
aliases the first 4 KiB of RAM at `0x1000_0000`. Because the array is read
combinationally on three ports, Vivado implements it as distributed RAM
(LUTRAM), not block RAM.

## VCF Datapath

Audio enters on `s_axis` as 32-bit stereo words `{R[31:16], L[15:0]}` and
leaves on `m_axis` in the same format. With CTRL.enable = 0 the block is a
zero-latency bypass. With enable = 1 one sample is in flight at a time: the
sample is latched, both channel cores run the state-variable filter, and the
selected output (low-pass, high-pass, or band-pass) is held on `m_axis` until
`m_axis_tready`. `tlast` follows the input sample.

Each channel computes, per sample, in signed Q1.15 with rounding and
saturation:

```text
hp = x - lp - q·bp
bp = bp + f·hp
lp = lp + f·bp
```

When the input is silent and all three states are below the LCO threshold,
the state is cleared to stop residual limit cycles.

Filter parameters are written to shadow registers and become active
atomically. A CTRL write with bit 2 set arms the commit; each channel copies
all shadows to its active set at the first zero crossing after the arm, or
after a timeout of 2400 filtered samples (50 ms at 48 kHz). Any later register
write cancels a pending commit, so a preset is never applied half way.

## Clock and Reset

The design uses one clock (`s_axi_aclk`, 100 MHz on the KR260) and one
active-low reset (`s_axi_aresetn`). The CPU additionally stays in reset until
the bootloader releases it and while CPU_CTRL[0] is 0.
