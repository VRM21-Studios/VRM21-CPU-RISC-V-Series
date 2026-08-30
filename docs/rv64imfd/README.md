# RV64IMFD CPU Core

## Overview

`vrm_cpu_rv64_core` is a 64-bit RISC-V processor core implementing the **RV64IMFD** ISA subset used by the VRM21-Studios RISC-V CPU Series.

The core combines a pipelined 64-bit integer datapath with dedicated Multiply/Divide and Floating-Point execution units.

The architecture is organized around a conventional five-stage pipeline:

```text
IF → ID → EX → MEM → WB
```

with dedicated execution resources for:

* RV64I integer operations
* RV64M multiplication and division
* RV64F single-precision floating-point operations
* RV64D double-precision floating-point operations
* Integer/floating-point register-domain conversion and movement
* Load/store operations
* Conditional branches and jumps
* Machine-mode interrupt handling
* `MRET`
* `WFI`

The core is designed as a modular processor component that can be integrated into a larger SoC through the associated wrapper and memory/peripheral infrastructure.

---

## Core Features

### 64-bit Integer Datapath

* 64-bit program counter
* 64-bit ALU
* 32 × 64-bit integer registers (`x0`–`x31`)
* Hardwired zero behavior for `x0`
* Immediate arithmetic and logical operations
* Register-register arithmetic and logical operations
* 64-bit and 32-bit integer instruction forms
* Shift operations
* Comparison operations
* `LUI`
* `AUIPC`
* `JAL`
* `JALR`
* Conditional branches

### Multiply / Divide

The RV64M execution path is provided by the dedicated:

```text
vrm_mdu_rv64m
```

The CPU supports multi-cycle MDU operation with dedicated pipeline stall handling.

The MDU provides the multiply/divide functionality required by the supported RV64M instruction subset.

### Floating Point

The floating-point execution path is provided by:

```text
vrm_fpu_rv64fd
```

The CPU contains a separate floating-point register file:

```text
f0 ... f31
```

with each register holding 64 bits.

The integration supports:

* Single-precision floating-point operations
* Double-precision floating-point operations
* Floating-point loads and stores
* Floating-point arithmetic
* Floating-point conversion
* Floating-point/integer register movement
* Floating-point comparison
* Floating-point classification
* Integer ↔ floating-point register-domain routing
* NaN-boxing for 32-bit floating-point values stored in 64-bit FPRs

The standalone FPU is maintained as a separate hardware project and can therefore be verified independently from the CPU integration.

---

## Pipeline

The processor uses a five-stage pipeline:

```text
        ┌────┐
        │ IF │
        └─┬──┘
          │
        ┌─▼──┐
        │ ID │
        └─┬──┘
          │
        ┌─▼──┐
        │ EX │
        └─┬──┘
          │
        ┌─▼──┐
        │MEM │
        └─┬──┘
          │
        ┌─▼──┐
        │ WB │
        └────┘
```

Pipeline registers separate the major execution stages:

* IF/ID
* ID/EX
* EX/MEM
* MEM/WB

The execute stage contains the primary computational resources:

```text
                    ┌─────────────┐
                    │     ALU     │
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  EX                  │
        │                                      │
        │   ┌─────────┐       ┌─────────┐     │
        │   │   MDU   │       │   FPU   │     │
        │   └─────────┘       └─────────┘     │
        └──────────────────────────────────────┘
```

Detailed pipeline behavior is documented separately in:

* [`pipeline.md`](pipeline.md)
* [`architecture.md`](architecture.md)

---

## Register Files

The core maintains two independent register domains.

### Integer Register File

```text
x0  ... x31
64-bit each
```

`x0` is always read as zero and is protected from writeback.

### Floating-Point Register File

```text
f0  ... f31
64-bit each
```

The floating-point register file is physically and logically separate from the integer register file.

Cross-domain instructions use dedicated routing logic to transfer data between the two register files.

---

## Forwarding and Hazard Handling

The processor implements forwarding paths for both integer and floating-point operands.

### Integer Forwarding

An integer operand can be sourced from:

```text
ID/EX register
      │
      ├── EX/MEM result
      │
      └── MEM/WB result
```

This allows dependent integer instructions to consume recently generated results without always waiting for register-file writeback.

### Floating-Point Forwarding

The FPU datapath has corresponding forwarding paths for floating-point results.

This is particularly important for sequences such as:

```text
FLD
 ↓
FADD.D
 ↓
FMUL.D
```

where the result of one floating-point operation becomes the operand of the next.

### Load-Use Hazard

A dedicated load-use detector is used to stall the pipeline when a load result is required by the immediately following instruction.

### Multi-Cycle Units

The MDU and FPU have dedicated activity and stall control.

The processor can temporarily freeze the appropriate pipeline stages while waiting for multi-cycle execution to complete.

---

## Memory System

The CPU exposes a 64-bit data-memory interface:

```text
mem_addr
mem_wdata
mem_we
mem_rdata
mem_busy
mem_wstrb
```

The interface supports byte-level write strobes.

Supported integer load forms include:

```text
LB
LH
LW
LD
LBU
LHU
LWU
```

Store operations include:

```text
SB
SH
SW
SD
```

Floating-point memory operations use the same memory interface.

The memory datapath includes:

* Address generation
* Byte offset handling
* Write-strobe generation
* Store-data alignment
* Load-data extraction
* Sign extension
* Zero extension
* Floating-point load formatting
* NaN-boxing for 32-bit floating-point loads

Further details are provided in [`memory_system.md`](memory_system.md).

---

## Control Flow

Branches and jumps are resolved in the execute stage.

The core generates:

```text
branch_taken_ex
target_pc_ex
flush_ex
```

When a control-flow instruction changes the execution path, instructions from the incorrect path are flushed from the pipeline.

Supported control-flow mechanisms include:

* `JAL`
* `JALR`
* Conditional branches
* `MRET`
* `WFI`

The `JALR` target is aligned according to the RISC-V architectural requirement by clearing bit 0 of the generated target address.

---

## Interrupt System

The processor contains a simplified machine-mode interrupt mechanism intended for integration with the surrounding VRM21 SoC environment.

The core provides:

```text
irq
```

as an external interrupt input.

On an accepted interrupt:

1. The current program counter is stored in `mepc`.
2. The processor enters interrupt state.
3. The program counter is redirected to the configured interrupt vector.
4. Relevant pipeline state is flushed.
5. Additional interrupt entry is inhibited while already servicing an interrupt.

Interrupt return is performed through:

```text
MRET
```

The detailed interrupt behavior and current implementation assumptions are documented in [`interrupt_system.md`](interrupt_system.md).

---

## WFI Support

The core implements:

```text
WFI
```

When execution reaches the wait-for-interrupt state without an active interrupt, the core exposes:

```text
cpu_halt = 1
```

This signal can be used by the surrounding system to determine that the processor has entered its idle state.

An interrupt can release the processor from the WFI state.

---

## SoC Integration

The CPU core is designed to operate as part of a larger SoC.

The associated wrapper can provide system-level functionality such as:

* External memory interface
* Peripheral routing
* Interrupt synchronization
* Interrupt arbitration
* Local timer functionality
* System-level control

The core itself remains focused on instruction execution and the processor datapath.

This separation allows additional VRM21 hardware accelerators and peripherals to be connected without fundamentally changing the CPU execution pipeline.

---

# Documentation

The RV64IMFD documentation is divided into several focused documents.

| Document                                     | Description                                                                                                                                                   |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`architecture.md`](architecture.md)         | Overall RV64IMFD architecture, datapath organization, execution units, register routing, forwarding, control flow, interrupt entry, WFI, and SoC integration. |
| [`pipeline.md`](pipeline.md)                 | Detailed IF/ID/EX/MEM/WB pipeline organization, pipeline registers, stalls, flushes, and forwarding behavior.                                                 |
| [`isa_support.md`](isa_support.md)           | Supported RV64I, RV64M, RV64F, and RV64D instruction classes and the current implementation scope.                                                            |
| [`mdu.md`](mdu.md)                           | Multiply/Divide Unit architecture, supported operations, multi-cycle behavior, and CPU-MDU handshake.                                                         |
| [`fpu.md`](fpu.md)                           | CPU integration of the VRM21 floating-point unit, FPR routing, conversions, moves, comparisons, and floating-point execution.                                 |
| [`memory_system.md`](memory_system.md)       | Data-memory interface, load/store operations, alignment, byte strobes, load extraction, sign/zero extension, and floating-point memory handling.              |
| [`interrupt_system.md`](interrupt_system.md) | Interrupt entry, `mepc`, interrupt state, vector redirection, pipeline flushing, `MRET`, and `WFI`.                                                           |
| [`firmware.md`](firmware.md)                 | Firmware/test-program structure used to exercise the processor and its execution units.                                                                       |
| [`verification.md`](verification.md)         | Current verification strategy, simulation methodology, stress-test coverage, and observed test results.                                                       |
| [`limitations.md`](limitations.md)           | Known limitations, unsupported architectural features, verification boundaries, and items that should not yet be interpreted as full RISC-V compliance.       |

---

## Verification Status

The RV64IMFD core has been subjected to an integrated simulation stress test covering multiple processor subsystems in a single firmware sequence.

The current test exercises:

```text
RV64I
 ├── ADD
 ├── SUB
 └── SLLI

RV64M
 ├── MUL
 └── DIV

Memory
 ├── SD
 └── LD

Control Flow
 └── BNE

Floating Point
 ├── FLD
 ├── FADD.D
 └── FMUL.D

System
 └── WFI
```

The observed simulation results include:

```text
[ALU] x3 (ADD)    = 150
[ALU] x4 (SUB)    = 50
[ALU] x5 (SLLI)   = 400

[MDU] x6 (MUL)    = 5000
[MDU] x7 (DIV)    = 2

[MEM] x8 (LD)     = 5000
[MEM] x9 (LD)     = 2

[BRN] x10 (Loop)  = 0

[FPU] f2 (FADD.D) = 4062C00000000000
[FPU] f3 (FMUL.D) = 40B3880000000000
```

The floating-point results correspond to:

```text
100.0 + 50.0 = 150.0
100.0 × 50.0 = 5000.0
```

The test also reaches the expected `WFI` state:

```text
CPU HALT REACHED
```

This establishes a successful **basic integrated CPU execution test** across the integer ALU, MDU, memory path, branch logic, FPU datapath, and WFI mechanism.

The detailed verification methodology and test artifacts are documented in [`verification.md`](verification.md).

---

## Standalone FPU Validation

The CPU's FPU subsystem is based on the separate VRM21 FPU hardware implementation.

The standalone FPU has additionally been validated on FPGA.

This should be distinguished from full FPGA validation of the complete RV64IMFD processor:

```text
Standalone FPU
      │
      └── FPGA validated

RV64IMFD CPU
      │
      └── Integrated simulation verified
```

Therefore, successful standalone FPU FPGA validation demonstrates hardware operation of the FPU itself, while the CPU-level verification currently establishes correct integration through simulation.

---

## Firmware Test Structure

The integrated stress-test firmware intentionally avoids relying on floating-point integer conversion as the initial FPU integration test.

Floating-point operands are loaded directly from memory using:

```text
FLD
```

followed by:

```text
FADD.D
FMUL.D
```

This isolates the basic floating-point datapath from potential issues in:

```text
FCVT
FMV
```

or other cross-register conversion instructions.

The firmware also exercises an integer loop using:

```text
ADDI
BNE
```

before entering:

```text
WFI
```

This provides a compact end-to-end test of instruction fetch, decode, execution, memory access, writeback, control flow, floating-point execution, and processor halt behavior.

Further firmware details are available in [`firmware.md`](firmware.md).

---

## Current Status

| Area                                | Status              |
| ----------------------------------- | ------------------- |
| RV64 integer datapath               | Implemented         |
| RV64 ALU                            | Implemented         |
| RV64M MDU                           | Implemented         |
| RV64F/D FPU integration             | Implemented         |
| Integer/FPU register routing        | Implemented         |
| Load/store datapath                 | Implemented         |
| Byte write strobes                  | Implemented         |
| Pipeline forwarding                 | Implemented         |
| Load-use stall handling             | Implemented         |
| MDU stall handling                  | Implemented         |
| FPU stall handling                  | Implemented         |
| Branch/jump flushing                | Implemented         |
| Interrupt mechanism                 | Implemented         |
| `MRET`                              | Implemented         |
| `WFI`                               | Implemented         |
| Integrated simulation stress test   | Passed              |
| Standalone FPU FPGA validation      | Passed              |
| Complete CPU FPGA validation        | Not yet established |
| Full RISC-V compliance verification | Not yet established |
| Formal verification                 | Not yet established |

---

## Scope and Compliance

`vrm_cpu_rv64_core` should currently be considered an **RTL implementation of the supported RV64IMFD feature set**, rather than a formally certified RISC-V-compliant processor.

The presence of an instruction or functional block in the RTL does not by itself imply complete architectural compliance.

In particular, the current verification status should be interpreted as:

```text
RTL implementation
        ↓
Integrated simulation
        ↓
Selected instruction / subsystem validation
        ↓
Basic CPU stress test PASSED
```

rather than:

```text
Full RISC-V compliance suite
        ↓
Formal verification
        ↓
Complete SoC verification
        ↓
Production qualification
```

Known limitations and unverified areas are maintained in [`limitations.md`](limitations.md).

---

## Related Components

The RV64IMFD core relies on several modular VRM21 hardware components, including:

```text
vrm_alu_rv64i
vrm_mdu_rv64m
vrm_fpu_rv64fd
vrm_cpu_rv64_core
```

The modular structure allows each major execution unit to be developed and verified independently while still providing a coherent CPU architecture.

---

## Repository Structure

The relevant RV64IMFD documentation is organized as:

```text
docs/
└── rv64imfd/
    ├── README.md
    ├── architecture.md
    ├── pipeline.md
    ├── isa_support.md
    ├── mdu.md
    ├── fpu.md
    ├── memory_system.md
    ├── interrupt_system.md
    ├── firmware.md
    ├── verification.md
    └── limitations.md
```

The RTL implementation and simulation/testbench files remain in their respective source and test directories.

---

## Development Status

The RV64IMFD core is an active hardware-development project.

The current priority is to expand verification coverage beyond the existing integrated stress test, particularly for:

* Broader RV64I instruction coverage
* Complete RV64M operation coverage
* More comprehensive RV64F/D instruction coverage
* Floating-point conversion and move instructions
* Floating-point comparison and classification
* Additional load/store corner cases
* Pipeline hazard combinations
* Interrupt corner cases
* WFI/interrupt interaction
* Memory backpressure
* FPGA-level CPU validation
* Compliance-oriented testing

The documentation will be updated as additional verification results become available.
