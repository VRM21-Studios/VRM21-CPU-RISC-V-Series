# RV32I CPU Documentation

## Overview

This directory contains the technical documentation, verification results, firmware information, and waveform artifacts for the **VRM21-Studios RV32I CPU implementation**.

The processor core is implemented as a synthesizable 32-bit RISC-V processor based on the **RV32I base integer instruction set**.

The main CPU module is:

```text
vrm_cpu_rv32i_core
```

The design uses a conventional five-stage pipeline:

```text
IF → ID → EX → MEM → WB
```

and is intended for FPGA-oriented SoC integration, custom hardware acceleration systems, and future VRM21 processor development.

The implementation includes:

* 32-bit RV32I integer datapath
* 32 × 32-bit general-purpose registers
* Five-stage pipeline
* Integer ALU
* Data forwarding
* Load-use hazard detection
* Pipeline stalling
* Branch and jump handling
* Pipeline flushing
* Byte-enable memory interface
* Load extraction and sign/zero extension
* Machine-mode interrupt entry
* `MRET`
* `WFI`
* Hardware timer integration
* Interrupt arbiter integration
* Memory-mapped peripheral access
* Bare-metal firmware support

---

## Architecture Overview

The processor is organized into five major pipeline stages:

```text
                 +----------------+
                 | Instruction    |
                 | Memory        |
                 +-------+--------+
                         |
                         v
                  +------------+
                  |     IF     |
                  | Instruction|
                  |    Fetch   |
                  +-----+------+
                        |
                      IF/ID
                        |
                        v
                  +------------+
                  |     ID     |
                  | Instruction|
                  |   Decode   |
                  | Register RF|
                  +-----+------+
                        |
                      ID/EX
                        |
                        v
                  +------------+
                  |     EX     |
                  |    ALU     |
                  | Forwarding |
                  | Branch     |
                  +-----+------+
                        |
                     EX/MEM
                        |
                        v
                  +------------+
                  |    MEM     |
                  | Data Memory|
                  +-----+------+
                        |
                     MEM/WB
                        |
                        v
                  +------------+
                  |     WB     |
                  | Register   |
                  |  Writeback |
                  +------------+
```

The architecture also contains dedicated control paths for:

```text
Hazard Detection
Forwarding
Branch / Jump Flush
Interrupt Entry
WFI / CPU Halt
```

Detailed architecture information is available in [`01_architecture.md`](01_architecture.md).

---

# Documentation Index

## 1. Architecture

### [`01_architecture.md`](01_architecture.md)

Describes the internal microarchitecture of `vrm_cpu_rv32i_core`.

Topics include:

* Processor overview
* Design goals
* Five-stage pipeline
* Instruction Fetch
* Instruction Decode
* Register file
* Execute stage
* ALU interface
* Data forwarding
* Load-use hazard detection
* Branch and jump handling
* Memory interface
* Store-data formatting
* Load-data extraction
* Interrupt architecture
* `WFI`
* SoC wrapper
* Current architectural scope

This is the primary document for understanding how the CPU datapath operates.

---

## 2. Instruction Set

### [`02_instruction_set.md`](02_instruction_set.md)

Documents the instruction classes currently implemented by the RTL.

The supported instruction groups are:

| Category    | Supported Instructions                                                 |
| ----------- | ---------------------------------------------------------------------- |
| U-Type      | `LUI`, `AUIPC`                                                         |
| J-Type      | `JAL`                                                                  |
| I-Type ALU  | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| I-Type Load | `LB`, `LH`, `LW`, `LBU`, `LHU`                                         |
| I-Type Jump | `JALR`                                                                 |
| R-Type      | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`   |
| S-Type      | `SB`, `SH`, `SW`                                                       |
| B-Type      | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`                             |
| SYSTEM      | `WFI`, `MRET`                                                          |

The document also describes:

* Instruction encoding formats
* Immediate generation
* Register conventions
* Individual instruction behavior
* Unsupported instruction classes

The implementation is intentionally limited to the integer RV32I-oriented scope and does not currently implement extensions such as `M`, `F`, `D`, `A`, or `C`.

---

## 3. Memory Map

### [`03_memory_map.md`](03_memory_map.md)

Documents the memory-mapped architecture used by the RV32I SoC.

Current system map:

| Address Range               |  Size | Device                          |
| --------------------------- | ----: | ------------------------------- |
| `0x0000_0000 – 0x0000_0FFF` |  4 KB | System RAM                      |
| `0x0000_1000 – 0x0000_10FF` | 256 B | Hardware Timer                  |
| `0x0000_2000 – 0x0000_20FF` | 256 B | Interrupt Arbiter               |
| `>= 0x0000_2100`            |     — | Application / Accelerator Space |

The memory map therefore separates processor memory from system-level control peripherals.

### System RAM

The current system RAM is:

```text
Base : 0x00000000
Size : 4 KB
End  : 0x00001000
```

It is used for:

* Program code
* Read-only data
* Writable data
* BSS
* Stack

The current stack top is:

```text
0x00001000
```

### Hardware Timer

The timer is mapped at:

```text
0x00001000
```

with registers:

```text
0x00  CTRL
0x04  COMPARE
0x08  COUNTER
0x0C  STATUS
```

### Interrupt Arbiter

The interrupt arbiter is mapped at:

```text
0x00002000
```

with:

```text
0x00  PENDING
0x04  ENABLE
0x08  CLEAR
```

The remaining address space is intentionally available for future application-specific hardware and accelerators.

---

## 4. Verification

### [`04_verification.md`](04_verification.md)

Documents the verification strategy for both the CPU core and the SoC wrapper.

Verification is divided into two levels:

```text
Core-Level Verification
        +
Wrapper-Level Verification
```

### Core-Level Verification

The core testbench covers:

* Integer ALU operations
* Immediate operations
* Loads
* Stores
* Byte enables
* Sign extension
* Zero extension
* Forwarding
* Load-use hazards
* Pipeline stalls
* Branch flushing
* Jumps
* `WFI`
* Interrupt entry
* `MRET`

The core testbench also contains instruction-encoding helpers for:

```text
asm_r()
asm_i()
asm_s()
asm_b()
asm_u()
asm_j()
```

allowing test programs to be assembled directly inside the Verilog testbench.

### Wrapper-Level Verification

The wrapper verification environment integrates:

```text
vrm_cpu_rv32i_core
        |
        +-- vrm_timer
        |
        +-- vrm_irq_arbiter
        |
        +-- External RAM
```

and verifies:

* MMIO address decoding
* Timer operation
* Interrupt generation
* Interrupt arbitration
* W1C behavior
* WFI wake-up
* ISR execution
* External memory access
* `MRET`

The complete timer-to-CPU interrupt path is therefore tested as:

```text
Timer
  ↓
Interrupt Arbiter
  ↓
CPU IRQ
  ↓
WFI Wake-up
  ↓
ISR
  ↓
MRET
  ↓
Normal Execution
```

---

## 5. Software and Firmware

### [`05_software.md`](05_software.md)

Documents the bare-metal software environment used with the RV32I processor.

The software stack is intentionally minimal:

```text
Architecture : RV32I
ABI          : ILP32
Runtime      : Bare Metal
```

The firmware consists of:

```text
boot.S
main.c
soc_map.h
link.ld
```

### Boot Flow

The startup sequence is:

```text
Reset
  ↓
_start
  ↓
reset_handler
  ↓
Initialize Stack
  ↓
main()
  ↓
WFI / Halt
```

The reset vector is:

```text
0x00000000
```

and the interrupt vector is:

```text
0x00000004
```

### Firmware Toolchain

The intended build environment uses a RISC-V GNU toolchain capable of generating RV32 code.

The firmware is compiled with:

```text
-march=rv32i
-mabi=ilp32
```

and uses a freestanding configuration without an operating system or standard runtime.

### Firmware Artifacts

The build flow produces:

```text
firmware.elf
firmware.mem
firmware.dump
```

where:

* `firmware.elf` is the linked executable
* `firmware.mem` is the Verilog memory image
* `firmware.dump` is the disassembly listing

The software documentation also describes MMIO access to the timer and interrupt arbiter.

---

# Verification Artifacts

## 6. Testbench Results

### [`06_tb_result.md`](06_tb_result.md)

Contains the recorded output and interpretation of the RV32I CPU testbench.

This document should be treated as the primary textual record of the current simulation results.

It complements `04_verification.md` by documenting the actual observed testbench execution rather than only describing the verification methodology.

---

## 7. CPU Core Waveform

### [`07_tb_vrm_cpu_rv32i_core_waveform.png`](07_tb_vrm_cpu_rv32i_core_waveform.png)

Waveform capture from the core-level RV32I CPU testbench.

The waveform provides visual evidence of internal simulation behavior such as:

* Clock and reset
* Program counter
* Instruction execution
* Pipeline activity
* Register-related signals
* Memory transactions
* Control-flow behavior
* Hazard handling

---

## 8. CPU Wrapper Waveform

### [`08_tb_vrm_cpu_wrapper_waveform.png`](08_tb_vrm_cpu_wrapper_waveform.png)

Waveform capture from the SoC wrapper-level testbench.

It provides visual evidence of the interaction between:

```text
CPU
Timer
Interrupt Arbiter
External Memory
IRQ
WFI
MRET
```

and complements the wrapper-level verification results documented in `04_verification.md`.

---

# Processor Feature Summary

| Feature                               | Status                                |
| ------------------------------------- | ------------------------------------- |
| RV32I integer datapath                | Implemented                           |
| 32 × 32-bit GPR                       | Implemented                           |
| Five-stage pipeline                   | Implemented                           |
| Integer ALU                           | Implemented                           |
| Data forwarding                       | Implemented                           |
| Load-use hazard detection             | Implemented                           |
| Pipeline stalls                       | Implemented                           |
| Branch handling                       | Implemented                           |
| Jump handling                         | Implemented                           |
| Pipeline flushing                     | Implemented                           |
| Byte-enable memory interface          | Implemented                           |
| Byte / halfword / word loads          | Implemented                           |
| Sign / zero extension                 | Implemented                           |
| `WFI`                                 | Implemented                           |
| `MRET`                                | Implemented                           |
| Machine-mode interrupt mechanism      | Implemented                           |
| Hardware timer                        | Implemented in SoC wrapper            |
| Interrupt arbiter                     | Implemented in SoC wrapper            |
| Bare-metal firmware                   | Available                             |
| Core-level simulation verification    | Available                             |
| Wrapper-level simulation verification | Available                             |
| FPGA validation                       | Refer to current verification records |

---

# SoC Integration Model

The RV32I processor is designed as a reusable CPU core rather than as a monolithic SoC.

A simplified system-level architecture is:

```text
                    +----------------------+
                    |   vrm_cpu_rv32i     |
                    |        _core         |
                    +----------+-----------+
                               |
                    +----------+----------+
                    |                     |
                    v                     v
              Instruction             Data / MMIO
                Memory                  Interface
                                          |
                         +----------------+----------------+
                         |                |                |
                         v                v                v
                    System RAM        Timer         IRQ Arbiter
                    0x0000_0000       0x1000          0x2000
                                          |
                                          v
                                    CPU Interrupt
```

Addresses outside the local peripheral regions can be routed to external memory or application-specific accelerator space.

This provides a straightforward path for integrating future VRM21 hardware blocks such as:

* DSP accelerators
* FFT cores
* DWT cores
* FIFO controllers
* RAM controllers
* Audio-processing hardware
* Custom FPGA peripherals

---

# Design Philosophy

The RV32I implementation follows a modular hardware-development approach.

The CPU is kept relatively small while system-level functions are provided through separate components.

```text
CPU Core
  |
  +-- ALU
  |
  +-- Pipeline / Hazard Control
  |
  +-- Memory Interface
  |
  +-- Interrupt Interface
          |
          +-- Timer
          |
          +-- IRQ Arbiter
```

This separation allows individual hardware blocks to be developed and verified independently.

It also provides a foundation for extending the processor into a larger VRM21-Studios SoC containing dedicated hardware accelerators.

---

# Current Scope

The current processor targets the RV32I base integer architecture together with the system-control functionality required by the current SoC design.

The current RTL does **not** implement:

* RV32M multiplication/division
* RV32A atomic instructions
* RV32F floating point
* RV32D double precision
* RV32C compressed instructions
* General CSR instruction support
* `FENCE`
* `ECALL`
* `EBREAK` as a normal implemented CPU instruction

`WFI` and `MRET` are explicitly recognized by the current implementation.

Therefore, this project should be described as an **RV32I-oriented processor implementation with selected machine-level system functionality**, rather than as a complete implementation of every RISC-V privileged or optional extension.

---

# Verification Philosophy

The verification documentation intentionally distinguishes between:

```text
RTL Simulation
```

and:

```text
FPGA Hardware Validation
```

Passing a simulation testbench demonstrates correct behavior under the modeled test conditions, but it does not automatically constitute physical FPGA validation.

The current documentation therefore keeps these claims separate and should be updated whenever additional hardware validation is performed.

---

# Document Relationship

The documentation is intended to be read in roughly this order:

```text
01_architecture.md
        ↓
02_instruction_set.md
        ↓
03_memory_map.md
        ↓
04_verification.md
        ↓
05_software.md
        ↓
06_tb_result.md
        ↓
07_core_waveform.png
        ↓
08_wrapper_waveform.png
```

For a quick architectural overview, start with `01_architecture.md`.

For instruction-level details, see `02_instruction_set.md`.

For software and MMIO integration, see `03_memory_map.md` and `05_software.md`.

For actual simulation evidence, see `06_tb_result.md` and the waveform artifacts.

---

# Repository Context

The RV32I core is the 32-bit processor member of the **VRM21-CPU-RISC-V-Series**.

It provides the baseline integer processor architecture on which more capable processor variants can be developed.

The repository also contains the RV64IMFD processor, which extends the architectural scope into:

```text
RV64I
+ M
+ F
+ D
```

The two cores are therefore intended to form related members of the same processor-development series rather than identical implementations.

---

## Status

The RV32I documentation reflects the current RTL and verification artifacts available in this repository.

As the processor and SoC evolve, the documentation should be updated together with:

* RTL changes
* Testbench changes
* Firmware changes
* Memory-map changes
* Verification results
* FPGA validation results
* Waveform artifacts

This keeps the documentation aligned with the actual hardware implementation rather than treating the documentation as an independent specification.
