# RV64IMFD Core Documentation

## Overview

This document set describes the architecture, implementation, verification flow, and current development status of the **VRM21-Studios RV64IMFD RISC-V CPU Core**.

The RV64IMFD implementation extends the previously developed RV32I CPU architecture into a 64-bit processor and integrates:

* RV64I integer processing
* RV64M integer multiplication and division
* RV64F floating-point operations
* RV64D double-precision floating-point operations
* Integer and floating-point register files
* Data forwarding and pipeline hazard handling
* Interrupt handling
* Machine-mode return and wait-for-interrupt support
* Memory-mapped timer
* Interrupt arbiter
* 64-bit data memory interface with byte strobes
* GCC-based bare-metal firmware support

The design is intended to serve as a reusable RISC-V CPU core within the broader VRM21-Studios hardware architecture.

---

## Architecture Overview

The processor is organized as a pipelined RV64 core with dedicated execution units for integer, multiplication/division, and floating-point operations.

```text
                    +----------------------+
                    |   Instruction Input  |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |   Instruction Fetch |
                    |        / Decode      |
                    +----------+-----------+
                               |
                         ID / EX Pipeline
                               |
          +--------------------+--------------------+
          |                    |                    |
          v                    v                    v
    +-----------+       +------------+       +-------------+
    | RV64I ALU |       |    MDU     |       |    FPU      |
    |           |       | RV64M      |       | RV64F / D   |
    +-----------+       +------------+       +-------------+
          |                    |                    |
          +--------------------+--------------------+
                               |
                               v
                    +----------------------+
                    |      EX / MEM        |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |    Memory Access     |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |      Writeback       |
                    +----------------------+
```

The core uses separate integer and floating-point register files:

* `x0`–`x31`: 64-bit integer registers
* `f0`–`f31`: 64-bit floating-point registers

---

## Supported ISA Extensions

The target ISA is:

```text
RV64IMFD
```

Where:

| Extension | Description                             |
| --------- | --------------------------------------- |
| `I`       | Base 64-bit integer ISA                 |
| `M`       | Integer multiplication and division     |
| `F`       | Single-precision floating-point support |
| `D`       | Double-precision floating-point support |

The implementation also contains selected machine-level functionality required by the current SoC integration, including interrupt entry, `MRET`, and `WFI` handling.

ISA support should be considered **implementation-specific** until the complete verification suite has been completed.

---

## Main RTL Components

The RV64IMFD system is composed of several major RTL blocks.

### CPU Core

```text
vrm_cpu_rv64_core
```

The main pipelined processor core.

Responsibilities include:

* Program counter management
* Instruction fetch
* Instruction decode
* Integer register file access
* Floating-point register file access
* ALU execution
* MDU control
* FPU control
* Branch and jump handling
* Pipeline control
* Data forwarding
* Load-use hazard handling
* Interrupt handling
* Memory interface generation
* Writeback

---

### Integer ALU

```text
vrm_alu_rv64i
```

Provides the RV64I integer arithmetic and logical operations used by the processor pipeline.

---

### Multiply/Divide Unit

```text
vrm_mdu_rv64m
```

Implements the RISC-V `M` extension.

Supported operation groups include:

```text
MUL
MULH
MULHSU
MULHU
DIV
DIVU
REM
REMU
```

and the corresponding 32-bit word operations:

```text
MULW
DIVW
DIVUW
REMW
REMUW
```

The multiplier path is intended to infer FPGA DSP resources where supported.

The divider uses an iterative radix-2 implementation and includes fast handling for architectural corner cases such as:

* Division by zero
* Signed division overflow

Further details are documented in [`mdu.md`](mdu.md).

---

### Floating-Point Unit

```text
vrm_fpu_rv64fd
```

The FPU wrapper integrates the floating-point execution lanes used by the processor.

The FPU architecture separates operations into functional lanes, including:

* Addition/subtraction
* Multiplication
* Division
* Square root
* Conversion
* Miscellaneous floating-point operations
* Mathematical functions

The detailed FPU implementation is maintained in the dedicated:

**VRM21-FPU-Series**

repository.

The CPU repository integrates the FPU at the processor level rather than duplicating the internal FPU implementation.

See [`fpu.md`](fpu.md) for the CPU/FPU integration details.

---

## Pipeline

The current CPU architecture uses a pipelined datapath containing the following major stages:

```text
IF → ID → EX → MEM → WB
```

### IF — Instruction Fetch

Responsible for:

* Program counter management
* Instruction memory interface
* Branch/jump target selection
* Interrupt entry

### ID — Instruction Decode

Responsible for:

* Opcode decoding
* Immediate generation
* Register file reads
* Instruction classification
* ALU/MDU/FPU operation selection
* Pipeline control generation

### EX — Execute

Responsible for:

* Integer ALU operations
* Branch comparison
* Address calculation
* MDU execution
* FPU execution
* Store-data alignment
* Write-strobe generation

### MEM — Memory Access

Responsible for:

* Data memory interface
* Load/store control
* Memory transaction synchronization

### WB — Writeback

Responsible for:

* Integer register writeback
* Floating-point register writeback
* Load-data extraction
* Floating-point result routing

Further pipeline details are documented in [`pipeline.md`](pipeline.md).

---

## Hazard and Stall Handling

The processor currently implements dedicated control for several pipeline hazards.

### Load-Use Hazard

A dependent instruction following a load may require the pipeline to stall until the loaded data becomes available.

### MDU Stall

Iterative division requires multiple cycles. The processor therefore freezes the relevant pipeline stages while the MDU operation is active.

### FPU Stall

Floating-point operations may have different execution latencies. The CPU therefore treats the FPU as a multi-cycle execution resource and stalls the appropriate pipeline stages until the result is available.

### Memory Stall

External memory transactions can indicate a busy condition through:

```text
mem_busy
```

The CPU uses this signal to freeze the relevant pipeline state.

### Control Hazard

Taken branches and jumps generate a pipeline flush so that instructions fetched from the wrong path are discarded.

---

## Memory Interface

The CPU exposes a 64-bit data-memory interface:

```text
mem_addr
mem_wdata
mem_we
mem_wstrb
mem_rdata
mem_busy
```

The byte-enable signal:

```text
mem_wstrb[7:0]
```

allows byte-level write selection for the 64-bit data bus.

The core also contains load extraction logic for:

```text
LB
LBU
LH
LHU
LW
LWU
LD
```

Store operations similarly support byte, half-word, word, and double-word accesses.

---

## SoC Integration

The CPU is integrated through:

```text
vrm_cpu_rv64_wrapper
```

The wrapper provides local memory-mapped peripherals and separates them from the external memory interface.

Current internal peripherals include:

```text
Hardware Timer
Interrupt Arbiter
```

The wrapper also synchronizes external interrupt sources before presenting them to the CPU interrupt path.

---

## Memory Map

The current memory map is defined in:

```text
include/vrm_soc_map_rv64.vh
```

The initial architecture contains:

| Region            |                                     Address Range | Function                                    |
| ----------------- | ------------------------------------------------: | ------------------------------------------- |
| Timer             | `0x0000_0000_0000_0000` – `0x0000_0000_0000_00FF` | Hardware timer                              |
| IRQ               | `0x0000_0000_0000_1000` – `0x0000_0000_0000_10FF` | Interrupt arbiter                           |
| Main RAM          | `0x0000_0000_0000_4000` – `0x0000_0000_0000_7FFF` | Unified data/program RAM                    |
| Accelerator space |                    `0x0000_0000_4000_0000` onward | Reserved for future accelerator integration |

The accelerator region is reserved for future expansion and does not imply that a corresponding accelerator is currently part of the validated RV64IMFD implementation.

---

## Interrupt Architecture

The current interrupt path consists of:

```text
External IRQ Sources
        |
        v
2-Stage Synchronizer
        |
        v
Interrupt Arbiter
        |
        v
CPU IRQ Input
```

The internal timer occupies interrupt source bit `0`.

External interrupt sources are synchronized before entering the interrupt arbiter.

The interrupt arbiter provides:

* Pending interrupt tracking
* Interrupt enable masking
* Rising-edge detection
* Software clearing of pending interrupts

The CPU prevents repeated interrupt entry while already inside the current interrupt handler.

---

## Firmware

A bare-metal firmware environment is provided for the RV64IMFD processor.

The firmware flow uses:

```text
boot.S
   |
   v
reset_handler
   |
   v
main()
```

The linker script defines the processor RAM region and places the stack at the upper end of the available RAM.

The firmware is built using the RISC-V GCC toolchain with:

```text
-march=rv64imfd
-mabi=lp64d
```

The resulting ELF image can be converted into a Verilog memory initialization file for simulation.

Firmware documentation is provided in [`firmware.md`](firmware.md).

---

## Verification

Verification is divided into several levels.

### Unit-Level Verification

Individual execution units are tested independently where applicable:

* RV64 ALU
* MDU
* FPU
* Timer
* Interrupt arbiter
* Memory interface logic

### Core-Level Verification

The RV64IMFD CPU testbench is intended to verify:

* Integer instructions
* Load/store operations
* Branches and jumps
* Pipeline hazards
* MDU operations
* FPU operations
* Interrupt handling
* Timer interaction
* Firmware execution

### FPGA Validation

FPGA validation is treated separately from simulation.

A module or subsystem should not be considered FPGA-validated solely because its RTL simulation passes.

The current validation status is documented in [`verification.md`](verification.md).

---

## Development Status

The RV64IMFD core is under active development.

Current implementation work includes:

* RV64I processor integration
* RV64M MDU integration
* RV64F/D FPU integration
* Pipeline control
* Memory interface
* Timer and interrupt infrastructure
* Bare-metal GCC firmware
* Simulation environment

Verification coverage is still being expanded.

Therefore, this documentation describes the **current implementation architecture**, not a claim of complete architectural compliance.

---

## Future Expansion

The architecture intentionally leaves room for future VRM21-Studios hardware blocks.

Potential future integration includes:

* DSP accelerators
* Audio processing hardware
* Custom coprocessors
* Synthesizer-related hardware
* AXI-connected accelerator blocks

Reserved address ranges should therefore be considered part of the SoC expansion strategy rather than evidence of completed accelerator implementations.

---

## Related Documentation

* [`architecture.md`](architecture.md)
* [`pipeline.md`](pipeline.md)
* [`isa_support.md`](isa_support.md)
* [`mdu.md`](mdu.md)
* [`fpu.md`](fpu.md)
* [`memory_system.md`](memory_system.md)
* [`interrupt_system.md`](interrupt_system.md)
* [`firmware.md`](firmware.md)
* [`verification.md`](verification.md)
* [`limitations.md`](limitations.md)

---

## Related VRM21-Studios Projects

The RV64IMFD core builds upon the earlier RV32I CPU development and integrates the dedicated VRM21 floating-point subsystem.

The FPU implementation is maintained separately in the **VRM21-FPU-Series** repository, while this project focuses on CPU-level integration and SoC architecture.

---

## Status Summary

| Component               | Status                            |
| ----------------------- | --------------------------------- |
| RV64I Core              | In development                    |
| RV64M MDU               | Implemented, verification ongoing |
| RV64F/D FPU Integration | Implemented, verification ongoing |
| Pipeline                | Implemented, verification ongoing |
| Memory Interface        | Implemented                       |
| Timer                   | Implemented                       |
| Interrupt Arbiter       | Implemented                       |
| GCC Firmware            | Initial environment available     |
| Simulation              | In development                    |
| FPGA Validation         | Pending / ongoing                 |
| Full ISA Compliance     | Not yet claimed                   |

**Important:** Passing individual simulations does not constitute complete RV64IMFD ISA compliance or FPGA validation.
