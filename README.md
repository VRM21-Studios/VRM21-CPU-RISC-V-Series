# VRM RISC-V CPU Series

A collection of custom **RISC-V processor cores and supporting RTL components** developed by VRM21 Studios for FPGA-based digital systems.

This repository is the starting point of the VRM RISC-V CPU series, focusing on modular processor architecture, pipelined execution, hazard handling, data forwarding, and FPGA-oriented RTL implementation.

The project is intended to evolve into a family of processor cores with different ISA extensions and architectural capabilities.

---

## Current Scope

The current repository checkpoint contains:

* A 32-bit pipelined RISC-V-oriented processor core
* A dedicated 32-bit Arithmetic Logic Unit (ALU)
* Instruction fetch interface
* Data memory interface
* Register file
* Pipeline registers
* Load-use hazard detection
* Data forwarding
* Branch and jump handling
* Basic interrupt and return-from-interrupt control
* WFI-related processor halt behavior
* Debug access to register `x1`

The architecture is under active development, and full ISA coverage and architectural compliance are not claimed at this checkpoint.

---

## Repository Structure

```text
VRM-RISC-V-CPU/
|
├── rtl/
│   ├── vrm_cpu_rv32i_core.v
│   ├── vrm_alu.v
│   └── ...
|
├── tb/
│   ├── ...
|
├── result/
│   └── ...
|
├── docs/
│   └── ...
|
└── README.md
```

The repository structure will expand as additional processor variants, verification environments, and supporting documentation are added.

---

# Current Modules

## `vrm_cpu_rv32i_core`

A 32-bit pipelined processor core implementing an RV32I-oriented datapath and control architecture.

The processor uses a classic five-stage pipeline:

```text
+----------------+
| Instruction    |
| Fetch (IF)     |
+-------+--------+
        |
        v
+----------------+
| Instruction    |
| Decode (ID)    |
+-------+--------+
        |
        v
+----------------+
| Execute (EX)   |
+-------+--------+
        |
        v
+----------------+
| Memory (MEM)   |
+-------+--------+
        |
        v
+----------------+
| Writeback (WB) |
+----------------+
```

### Main Features

* 32-bit datapath
* 32-bit program counter
* 32 general-purpose registers
* Five-stage pipeline
* Load-use hazard detection
* EX/MEM data forwarding
* MEM/WB data forwarding
* Immediate generation for supported instruction formats
* Arithmetic and logical operations
* Conditional branches
* JAL
* JALR
* LUI
* AUIPC
* Load and store memory interface
* MRET control flow
* WFI-related halt handling
* Basic interrupt entry mechanism
* Debug visibility for register `x1`

---

## Pipeline Stages

### Instruction Fetch (IF)

The fetch stage provides the current program counter through:

```text
pc_out
```

The corresponding instruction is returned through:

```text
instr_in
```

The program counter advances sequentially or is redirected by a branch, jump, interrupt, or MRET operation.

---

### Instruction Decode (ID)

The decode stage:

* Extracts instruction fields
* Generates immediate values
* Reads register operands
* Decodes instruction control signals
* Determines ALU operation
* Detects branch and jump instructions
* Identifies supported system-control instructions

The register file contains 32 registers with 32-bit width.

Register `x0` is treated as a constant zero value during register reads, and register writes to `x0` are suppressed.

---

### Execute (EX)

The execute stage performs:

* ALU operations
* Operand forwarding
* Branch condition evaluation
* Branch target calculation
* Jump target calculation
* JALR address generation

The datapath includes forwarding paths from later pipeline stages to reduce data hazards.

---

### Memory Access (MEM)

The memory stage exposes a simple data memory interface:

```text
mem_addr
mem_wdata
mem_we
mem_rdata
```

Store operations assert `mem_we`.

Load operations receive data through `mem_rdata`.

The current architecture does not expose an explicit memory-side ready/valid handshake.

---

### Writeback (WB)

The writeback stage selects between:

* ALU result
* Memory read data

The selected value is written into the destination register when the instruction indicates that register writeback is required.

---

# Hazard Handling

The current processor implements two primary mechanisms for pipeline data hazards.

## Load-Use Hazard Detection

A pipeline stall is generated when an instruction in the execute stage performs a memory read and its destination register is required by the instruction currently in decode.

The hazard detection logic prevents the dependent instruction from progressing until the required value becomes available through the pipeline.

---

## Data Forwarding

The processor implements forwarding from:

```text
EX/MEM
   |
   v
MEM/WB
```

Forwarding is available for the two primary ALU operands.

This reduces unnecessary pipeline stalls for results produced by earlier arithmetic instructions.

---

# Control Flow

The processor includes support for:

* Conditional branch operations
* JAL
* JALR
* MRET

Taken control-flow instructions trigger pipeline flushing to remove younger instructions that were fetched using the previous sequential program flow.

A branch or jump target is calculated in the execute stage.

---

# Interrupt and WFI Control

The current core contains a basic interrupt mechanism.

When an interrupt request is accepted:

1. The current PC is stored in `MEPC`.
2. The processor redirects execution to a fixed interrupt vector.
3. The processor enters interrupt-service state.
4. Pipeline state associated with younger instructions is cleared.

MRET restores execution from the stored `MEPC` value.

The core also includes WFI-related halt behavior. When the corresponding system instruction reaches the relevant pipeline stage, the CPU enters a halted state until an accepted interrupt releases the processor.

The current implementation is intended as an initial interrupt and low-power control mechanism and may evolve in future revisions.

---

# ALU

## `vrm_alu`

A 32-bit combinational Arithmetic Logic Unit used by the processor core.

### Supported Operations

|   Control | Operation | Description            |
| --------: | --------- | ---------------------- |
| `4'b0000` | ADD       | Addition               |
| `4'b0001` | SUB       | Subtraction            |
| `4'b0010` | SLL       | Shift Left Logical     |
| `4'b0011` | SLT       | Signed Set Less Than   |
| `4'b0100` | XOR       | Bitwise XOR            |
| `4'b0101` | SRL       | Shift Right Logical    |
| `4'b0110` | OR        | Bitwise OR             |
| `4'b0111` | AND       | Bitwise AND            |
| `4'b1000` | SRA       | Shift Right Arithmetic |

The ALU also provides a `zero` output that is asserted when the resulting value is zero.

Shift operations use the lower five bits of `src_b` as the shift amount.

---

# Interfaces

## Instruction Interface

```text
pc_out
instr_in
```

The processor provides the current program counter and receives a 32-bit instruction word from an external instruction memory or instruction storage system.

---

## Data Memory Interface

```text
mem_addr
mem_wdata
mem_we
mem_rdata
```

The current implementation uses a simple synchronous processor-side memory interface.

A future version may introduce explicit transaction control or AXI-based interfaces through a separate wrapper layer.

---

## Debug Interface

```text
debug_reg_x1
```

Provides direct visibility of general-purpose register `x1`.

This output is intended for basic debugging and processor-state observation during development.

---

# Design Philosophy

The VRM RISC-V CPU series is being developed with the following goals:

* Modular RTL architecture
* Clear pipeline boundaries
* Reusable processor components
* FPGA-oriented implementation
* Explicit hazard handling
* Deterministic pipeline behavior
* Separation between CPU core and external memory systems
* Progressive expansion of ISA and architectural features

The processor core is designed to serve as a foundation for future VRM CPU variants.

---

# Planned CPU Series

The long-term direction of this project includes multiple processor configurations.

Planned variants may include:

```text
VRM RISC-V CPU Series
|
+-- RV32I
|
+-- RV32IM
|
+-- RV64IMFD
|    |
|    +-- Integer Multiply / Divide
|    +-- Double-Width Integer Support
|    +-- Single-Precision Floating Point
|    +-- Double-Precision Floating Point
|
+-- FPU
|
+-- Future custom extensions
```

The exact architecture and implementation status of each variant will be documented independently as the corresponding RTL becomes available and verified.

---

# Verification Status

Verification infrastructure is currently under development.

Future testbenches are intended to cover:

* Reset behavior
* Register file behavior
* ALU operations
* Immediate instruction behavior
* Register-register operations
* Branch conditions
* JAL and JALR
* Load and store behavior
* Load-use hazards
* Forwarding paths
* Pipeline flush behavior
* Interrupt handling
* MRET behavior
* WFI behavior
* Program execution sequences

At this checkpoint, no general claim of complete RISC-V ISA compliance or FPGA hardware validation is made.

Verification status will be updated as dedicated testbenches and implementation results are added.

---

# Validation Levels

The project will use the following validation terminology:

| Status                    | Meaning                                                                      |
| ------------------------- | ---------------------------------------------------------------------------- |
| `Simulation Verified`     | Functionality verified through RTL simulation                                |
| `ISA Verified`            | Relevant instructions verified against a software or architectural reference |
| `Post-Synthesis Verified` | Behavior verified after synthesis-related processing                         |
| `Timing Verified`         | Timing closure achieved for a documented target FPGA configuration           |
| `FPGA Validated`          | Core tested on physical FPGA hardware                                        |
| `Experimental`            | Implementation exists but verification is incomplete                         |

Individual modules and future processor variants may have different validation levels.

---

# Toolchain

Primary development environment:

* **AMD Vivado**
* Verilog HDL
* RTL simulation
* FPGA implementation and timing analysis

Future processor variants may introduce additional simulation, software, or hardware verification tools.

---

# Current Status

**Development Status: Experimental / Active Development**

The current repository represents an early development checkpoint of the VRM RISC-V CPU series.

The present focus is on establishing:

* A working pipelined CPU architecture
* Reusable ALU infrastructure
* Pipeline hazard handling
* Data forwarding
* Basic control-flow support
* Interrupt and WFI mechanisms

Additional instruction support, processor variants, verification environments, and FPGA implementation results will be added progressively.

---

# Roadmap

Planned development areas include:

* Dedicated RV32I verification testbench
* Instruction-level verification
* Automated ISA test execution
* Pipeline stress testing
* Interrupt and WFI verification
* FPGA implementation
* Resource utilization analysis
* Timing analysis
* RV32IM extension
* RV64 processor implementation
* Floating-point unit development
* RV64IMFD processor variant
* Improved software integration and firmware support

The roadmap may evolve as the processor architecture develops.

---

# Related Projects

This repository is part of the broader VRM21 Studios FPGA and RTL development ecosystem.

Other VRM projects include:

* Reusable RTL infrastructure
* FPGA DSP processing cores
* Audio DSP systems
* RISC-V processor architectures
* FPGA accelerator architectures
* Research-oriented hardware implementations

Common low-level RTL dependencies may be maintained in the separate **VRM RTL Library** repository.

---

# License

Licensed under the MIT License.

Provided as-is, without warranty.
