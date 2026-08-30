# VRM RV32I CPU — Architecture

## 1. Overview

`vrm_cpu_rv32i_core` is a synthesizable 32-bit RISC-V processor implementing the RV32I base integer instruction set.

The CPU is designed as a compact pipelined processor for integration into FPGA-oriented SoC designs and hardware acceleration systems. The architecture separates instruction and data interfaces, allowing the processor to operate with independent instruction and data memory systems.

The design is organized as a five-stage pipeline:

1. Instruction Fetch (IF)
2. Instruction Decode (ID)
3. Execute (EX)
4. Memory Access (MEM)
5. Writeback (WB)

The processor also provides basic pipeline hazard handling, data forwarding, branch flushing, interrupt handling, and a `WFI`-based halt mechanism.

---

## 2. Design Goals

The CPU is intended to provide:

* RV32I integer instruction execution
* A compact synthesizable RTL implementation
* Five-stage pipelined execution
* Basic data forwarding
* Load-use hazard detection
* Branch and jump pipeline flushing
* Byte-enable support for data memory
* Load byte/halfword extraction and sign extension
* Machine-mode interrupt entry and return
* `WFI` support for interrupt-driven operation
* Simple external memory interfaces
* Easy integration with custom FPGA peripherals and accelerators

The design intentionally keeps the processor interface simple so that it can be connected directly to BRAM, distributed RAM, external memory controllers, MMIO peripherals, or custom accelerator blocks.

---

## 3. Top-Level Architecture

The processor core is divided into the following functional stages:

```text
                    +----------------------+
                    |   Instruction Memory |
                    +----------+-----------+
                               |
                               v
+---------+       +----------------------+       +----------------------+
|   PC    | ----> | IF / ID Pipeline Reg | ----> | Instruction Decode   |
+---------+       +----------------------+       +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | Register File / ID   |
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | ID / EX Pipeline Reg |
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | Execute / ALU        |
                                                | Forwarding           |
                                                | Branch Evaluation    |
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | EX / MEM Pipeline Reg|
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | Memory Access        |
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | MEM / WB Pipeline Reg|
                                                +----------+-----------+
                                                           |
                                                           v
                                                +----------------------+
                                                | Writeback             |
                                                +----------------------+
```

---

## 4. Pipeline Stages

### 4.1 Instruction Fetch — IF

The IF stage maintains the program counter (`pc`) and fetches the instruction from the external instruction memory interface.

The primary signals are:

* `pc_out`
* `instr_in`

Under normal operation, the program counter advances by 4 bytes:

```text
PC_next = PC + 4
```

The PC can instead be redirected by:

* Taken conditional branches
* `JAL`
* `JALR`
* Interrupt entry
* `MRET`

The reset vector is:

```text
PC = 0x00000000
```

The interrupt vector is currently hard-coded to:

```text
PC = 0x00000004
```

---

## 5. Instruction Decode — ID

The decode stage extracts the standard RISC-V instruction fields:

* `opcode`
* `rd`
* `rs1`
* `rs2`
* `funct3`
* `funct7`

The following immediate formats are generated:

* I-type
* S-type
* B-type
* U-type
* J-type

The decoder generates control signals for:

* Register write
* Memory read
* Memory write
* Branch
* Jump
* JALR
* LUI
* AUIPC
* WFI
* MRET
* ALU operation selection

---

## 6. Register File

The CPU contains 32 general-purpose 32-bit registers:

```text
x0 ... x31
```

Register `x0` is hardwired to zero by preventing write operations to register index zero.

The register file is initialized to zero in simulation.

The implementation also provides writeback-to-decode bypassing. This allows an instruction in the decode stage to observe the value being written back in the same cycle.

---

## 7. Execute Stage — EX

The execute stage performs:

* Arithmetic operations
* Logical operations
* Shift operations
* Comparison operations
* Address calculation
* Branch condition evaluation
* Jump target calculation

The ALU is implemented as an external module:

```text
vrm_alu
```

The CPU supplies:

```text
src_a
src_b
ctrl
```

and receives:

```text
result
zero
```

---

## 8. Data Forwarding

The processor implements forwarding from:

* EX/MEM
* MEM/WB

to the EX stage.

Two forwarding paths are provided:

```text
forward_a
forward_b
```

The priority is:

```text
EX/MEM
    |
    v
MEM/WB
    |
    v
Register File
```

This avoids unnecessary stalls for most ALU-to-ALU dependencies.

---

## 9. Load-Use Hazard Handling

A load instruction cannot provide its final data until the memory access stage has completed.

The CPU therefore detects a dependency between:

```text
ID/EX load destination
```

and:

```text
ID-stage rs1 / rs2
```

When a load-use dependency is detected:

```text
stall = 1
```

The pipeline prevents the dependent instruction from advancing while injecting a bubble into the ID/EX stage.

This allows sequences such as:

```asm
lw   x14, 0(x13)
addi x15, x14, 1
```

to execute correctly.

---

## 10. Branch and Jump Handling

Conditional branches are resolved in the EX stage.

Supported branch conditions include:

* BEQ
* BNE
* BLT
* BGE
* BLTU
* BGEU

When a branch or jump is taken:

```text
flush_ex = 1
```

The instruction currently entering the following pipeline stage is invalidated.

The target address is calculated as:

```text
Branch:
target = PC + B-immediate

JAL:
target = PC + J-immediate

JALR:
target = (rs1 + I-immediate) & ~1
```

---

## 11. Memory Interface

The CPU exposes a simple data-memory interface:

```text
mem_addr
mem_wdata
mem_be
mem_we
mem_rdata
```

The byte-enable signal is four bits wide:

```text
mem_be[3:0]
```

Each bit corresponds to one byte lane of the 32-bit data bus.

This allows the processor to perform:

* Byte stores
* Halfword stores
* Word stores

without requiring a separate bus-width conversion layer.

---

## 12. Store Data Formatting

For `SB`, the selected byte is replicated across all four data lanes.

For example:

```text
SB data = 0x0000000F
```

produces:

```text
mem_wdata = 0x0F0F0F0F
```

with only the selected byte-enable asserted.

For `SH`, the selected halfword is replicated:

```text
mem_wdata = 0xFFF6FFF6
```

with two adjacent byte lanes enabled.

For `SW`, the original 32-bit value is forwarded directly.

---

## 13. Load Data Extraction

The processor supports:

* `LB`
* `LH`
* `LW`
* `LBU`
* `LHU`

The returned memory word is shifted according to:

```text
mem_wb_alu_res[1:0]
```

The required byte or halfword is then extracted.

Signed loads perform sign extension.

Unsigned loads perform zero extension.

---

## 14. Interrupt Architecture

The core exposes a single interrupt input:

```text
irq
```

An interrupt is accepted when:

```text
irq == 1
```

and:

```text
in_isr == 0
```

The processor then:

1. Saves the current PC into `mepc`
2. Sets `in_isr`
3. Redirects execution to `0x00000004`
4. Flushes relevant pipeline state

The interrupt vector is therefore:

```text
0x00000004
```

The ISR returns using:

```asm
mret
```

which restores execution from `mepc`.

---

## 15. WFI Operation

The processor recognizes:

```text
WFI
```

and enters a halted state after the instruction reaches the writeback stage.

The external signal is:

```text
cpu_halt
```

The halt condition is:

```text
cpu_halt = WFI_in_WB && !irq_trigger
```

An interrupt therefore releases the CPU from the WFI state.

This mechanism is used by the SoC wrapper to allow the CPU to sleep while waiting for timer or external hardware events.

---

## 16. SoC Wrapper

The CPU can be integrated through:

```text
vrm_cpu_rv32i_wrapper
```

The wrapper adds:

* Hardware timer
* Interrupt arbiter
* MMIO address decoding
* External data-memory routing
* External interrupt inputs

The resulting architecture is:

```text
                 +---------------------+
                 |   RV32I CPU Core    |
                 +----------+----------+
                            |
                     Data Memory Bus
                            |
              +-------------+-------------+
              |                           |
              v                           v
       +-------------+             +-------------+
       | Timer       |             | IRQ Arbiter |
       | 0x1000      |             | 0x2000      |
       +-------------+             +-------------+
              |                           |
              +-------------+-------------+
                            |
                            v
                    External Memory /
                    Accelerator Space
```

---

## 17. Design Scope

The current implementation targets the RV32I base integer instruction set required by the processor design.

The implementation does not currently provide:

* Floating-point instructions
* Atomic instructions
* Compressed instructions
* Multiplication/division instructions
* General privileged instruction support
* `FENCE` execution
* Full CSR architecture

The currently recognized system instructions are:

* `WFI`
* `MRET`

This scope is intentional and keeps the initial CPU implementation compact and suitable for FPGA-oriented SoC development.s
