# VRM21 CPU RISC-V Series

A collection of custom RISC-V processor cores and supporting hardware developed as part of the **VRM21 Hardware/RTL Series**.

This repository focuses on the development of custom RISC-V CPU cores, their surrounding system components, verification environments, firmware support, and SoC-level integration.

The repository currently contains an **RV32I CPU subsystem** and an **RV64IMFD CPU subsystem**, together with supporting interrupt, timer, memory-mapped I/O, firmware, and verification infrastructure.

The RV64IMFD implementation extends the series toward a 64-bit processor architecture with integer multiplication/division and hardware floating-point support through the **F** and **D** extensions.

---

## Motivation

This project was developed as part of a self-directed study of computer architecture through practical RTL implementation.

Rather than studying processor architecture only from an ISA or software perspective, the project explores how instructions are decoded, executed, and moved through an actual hardware datapath. The RISC-V architecture provides an accessible and open foundation for studying concepts such as pipelining, hazard handling, memory interfaces, control logic, and processor state.

The primary objective of the project is therefore educational: to develop a deeper understanding of how a processor works by implementing and examining its architecture at the RTL level.

---

## Repository Status

| Component                        | Status                        |
| -------------------------------- | ----------------------------- |
| RV32I CPU Core                   | Available                     |
| RV32I Pipeline                   | Available                     |
| RV32I ALU                        | Available                     |
| RV32I Load/Store Unit            | Available                     |
| RV32I Byte Enable Support        | Available                     |
| RV32I Hazard Handling            | Available                     |
| RV32I Data Forwarding            | Available                     |
| RV32I Branch / Jump Handling     | Available                     |
| RV32I WFI Support                | Available                     |
| RV32I MRET Support               | Available                     |
| RV32I Interrupt Handling         | Available                     |
| RV32I Hardware Timer             | Available                     |
| RV32I Interrupt Arbiter          | Available                     |
| RV32I SoC Wrapper                | Available                     |
| RV32I Firmware                   | Available                     |
| RV32I Simulation Verification    | Available                     |
| RV32I FPGA Verification          | Verified                      |
| RV64IMFD CPU Core                | Available / Development Stage |
| RV64IMFD Pipeline                | Available / Development Stage |
| RV64I Integer ISA                | Available / Development Stage |
| RV64 M Extension                 | Available / Development Stage |
| RV64 F Extension                 | Available / Development Stage |
| RV64 D Extension                 | Available / Development Stage |
| RV64 MDU                         | Available / Development Stage |
| RV64 FPU                         | Available / Development Stage |
| RV64 Interrupt System            | Available / Development Stage |
| RV64 Hardware Timer              | Available / Development Stage |
| RV64 Interrupt Arbiter           | Available / Development Stage |
| RV64 SoC Wrapper                 | Available / Development Stage |
| RV64IMFD Firmware                | Available / Development Stage |
| RV64IMFD Simulation Verification | In Progress                   |
| RV64IMFD FPGA Verification       | Not Yet Verified              |
| VRM Synthesizer Series           | Under Development             |

> **FPGA Verification Note:** The RV32I implementation has been verified on FPGA as part of a system-level hardware integration. The specific application-level design used during FPGA validation is not included in this repository because its associated research work is currently unpublished.

> **RV64IMFD Verification Note:** The RV64IMFD implementation is currently in the development and simulation-verification stage. FPGA validation has not yet been completed.

> **Synthesizer Development Note:** The memory map and firmware environment currently contain a reserved/example region for the planned VRM Synthesizer Series. The oscillator-related interface is currently used only as a placeholder for future SoC integration and firmware testbench development. The synthesizer/oscillator implementation is not considered a completed or FPGA-validated component.

---

# Architecture Overview

The repository is organized by CPU architecture:

```text
VRM21-CPU-RISC-V-Series
│
├── rtl/
│   ├── rv32i/
│   │   ├── vrm_cpu_rv32i_core.v
│   │   ├── vrm_cpu_rv32i_wrapper.v
│   │   ├── vrm_irq_arbiter.v
│   │   ├── vrm_timer.v
│   │   └── ...
│   │
│   └── rv64imfd/
│       ├── vrm_cpu_rv64_core.v
│       ├── vrm_cpu_rv64_wrapper.v
│       ├── vrm_cpu_timer_64.v
│       ├── vrm_cpu_irq_arbiter_64.v
│       ├── ...
│       └── ...
│
├── tb/
│   ├── rv32i/
│   │   ├── tb_vrm_cpu_rv32i_core.sv
│   │   ├── tb_vrm_cpu_wrapper.sv
│   │   └── ...
│   │
│   └── rv64imfd/
│       ├── ...
│       └── ...
│
├── include/
│   ├── rv32i/
│   │   └── vrm_soc_map_rv32i.vh
│   │
│   └── rv64imfd/
│       └── vrm_soc_map_rv64.vh
│
├── gcc-firmware/
│   ├── rv32i/
│   │   ├── boot.S
│   │   ├── main.c
│   │   ├── soc_map.h
│   │   ├── link.ld
│   │   └── build.sh
│   │
│   └── rv64imfd/
│       ├── boot.S
│       ├── main.c
│       ├── soc_map.h
│       ├── link.ld
│       └── compiler.md
│
├── docs/
│   ├── rv32i/
│   │   └── ...
│   │
│   └── rv64imfd/
│       ├── README.md
│       ├── architecture.md
│       ├── pipeline.md
│       ├── isa_support.md
│       ├── mdu.md
│       ├── fpu.md
│       ├── memory_system.md
│       ├── interrupt_system.md
│       ├── firmware.md
│       ├── verification.md
│       └── limitations.md
│
└── README.md
```

The architecture-specific directory layout is intentional.

Each supported CPU architecture has its own implementation, verification environment, memory map, firmware, and documentation.

This allows new architectures to be introduced without mixing architecture-specific RTL and verification infrastructure.

---

# RV32I CPU

The RV32I processor is the first CPU implementation in the series and provides a 32-bit RISC-V integer processing subsystem.

The CPU uses a pipelined architecture with:

```text
IF → ID → EX → MEM → WB
```

where:

* **IF** — Instruction Fetch
* **ID** — Instruction Decode and Register Read
* **EX** — Execute, Branch, Jump and Forwarding
* **MEM** — Memory Access
* **WB** — Writeback

The implementation includes data forwarding, load-use hazard detection, branch and jump handling, interrupt support, and memory-mapped system peripherals.

---

## RV32I Supported Instruction Groups

### U-Type

* `LUI`
* `AUIPC`

### J-Type

* `JAL`

### I-Type

* `JALR`
* `ADDI`
* `SLTI`
* `SLTIU`
* `XORI`
* `ORI`
* `ANDI`
* `SLLI`
* `SRLI`
* `SRAI`

### R-Type

* `ADD`
* `SUB`
* `SLL`
* `SLT`
* `SLTU`
* `XOR`
* `SRL`
* `SRA`
* `OR`
* `AND`

### Load

* `LB`
* `LH`
* `LW`
* `LBU`
* `LHU`

### Store

* `SB`
* `SH`
* `SW`

### Branch

* `BEQ`
* `BNE`
* `BLT`
* `BGE`
* `BLTU`
* `BGEU`

### System Instructions

* `WFI`
* `MRET`

---

# RV64IMFD CPU

The RV64IMFD implementation is the second major processor architecture in the series.

It extends the integer RV32I concept toward a 64-bit architecture and adds hardware support for:

```text
RV64I
 ├── M — Integer Multiplication and Division
 ├── F — Single-Precision Floating Point
 └── D — Double-Precision Floating Point
```

The implementation is organized as a separate architecture rather than as a modification of the RV32I source tree.

The RV64IMFD subsystem includes:

* 64-bit integer datapath
* 64-bit program counter
* RV64 integer execution
* Multiply/divide unit
* Floating-point unit
* 64-bit memory interface
* Byte write strobes
* Memory-mapped timer
* Interrupt arbiter
* External interrupt synchronization
* SoC-level address decoding
* Bare-metal GCC firmware support

Detailed documentation is available under:

```text
docs/rv64imfd/
```

---

# RV64IMFD Pipeline

The RV64IMFD processor follows the same general pipelined philosophy as the RV32I implementation while extending the datapath and execution resources for 64-bit operation and floating-point instructions.

The general pipeline organization is:

```text
IF → ID → EX → MEM → WB
```

The architecture separates integer, memory, multiply/divide, and floating-point operations through their respective execution resources.

Detailed pipeline behavior is documented in:

```text
docs/rv64imfd/pipeline.md
```

---

# RV64 M Extension and MDU

The RV64 implementation includes a dedicated **Multiply/Divide Unit (MDU)** for the RISC-V `M` extension.

The M extension provides integer multiplication and division operations for the 64-bit architecture.

The MDU is responsible for operations including:

* `MUL`
* `MULH`
* `MULHSU`
* `MULHU`
* `DIV`
* `DIVU`
* `REM`
* `REMU`

The MDU implementation and its architectural behavior are documented separately in:

```text
docs/rv64imfd/mdu.md
```

---

# RV64 F and D Extensions

The RV64IMFD architecture includes hardware floating-point support through the VRM21 FPU subsystem.

The architecture supports:

```text
F → IEEE-754 single-precision operations
D → IEEE-754 double-precision operations
```

The FPU is integrated into the RV64 processor architecture rather than being treated as an external software-only floating-point implementation.

The FPU documentation covers:

* Supported floating-point operations
* Datapath organization
* Register interaction
* Integer/floating-point conversion
* F and D extension behavior
* FPU integration
* Verification methodology

Detailed documentation is available in:

```text
docs/rv64imfd/fpu.md
```

The standalone FPU hardware has also been validated independently on FPGA. The complete RV64IMFD CPU integration, however, has not yet undergone FPGA validation.

---

# RV64 Memory System

The RV64 system uses a 64-bit memory interface:

```text
Address   : 64-bit
Write Data: 64-bit
Read Data : 64-bit
Write Strobe: 8-bit
```

The byte write strobe allows individual byte lanes to be controlled during store operations.

The external memory interface therefore provides:

```text
ext_mem_addr
ext_mem_wdata
ext_mem_wstrb
ext_mem_we
ext_mem_rdata
ext_mem_busy
```

Local system peripherals are decoded inside the CPU wrapper, while external memory and future accelerators are accessed through the external memory interface.

Detailed information is documented in:

```text
docs/rv64imfd/memory_system.md
```

---

# RV64 Memory Map

The current RV64 system defines the following architectural regions:

| Address Range               | Region | Description                               |
| --------------------------- | ------ | ----------------------------------------- |
| `0x0000_0000 - 0x0000_00FF` | Tier 0 | Hardware Timer                            |
| `0x0000_1000 - 0x0000_10FF` | Tier 0 | Interrupt Arbiter                         |
| `0x0000_4000 - 0x0000_7FFF` | Tier 1 | Main Data Memory                          |
| `0x4000_0000 - 0x4000_0FFF` | Tier 2 | Reserved Synthesizer / Accelerator Region |

The Tier 2 region is intentionally reserved for future application accelerators.

In particular:

```text
0x0000_0000_4000_0000
```

is currently allocated as an example base address for the planned VRM Synthesizer Series.

This does **not** indicate that the oscillator implementation is currently a completed subsystem.

---

# Interrupt Architecture

The RV64 system extends the interrupt architecture used by the RV32I subsystem.

The architecture contains:

```text
External IRQ Sources
        │
        ▼
2-Stage Synchronizer
        │
        ▼
Interrupt Arbiter
        │
        ├── Timer IRQ
        │
        └── External IRQs
        │
        ▼
     CPU IRQ
```

The interrupt arbiter maintains:

* Pending interrupt state
* Interrupt enable mask
* Rising-edge detection
* Interrupt clearing
* Combined CPU interrupt trigger

The current source allocation is:

```text
IRQ bit 0      → Hardware Timer
IRQ bits 1-31  → External interrupt sources
```

External interrupt inputs are synchronized through a two-stage flip-flop structure before entering the interrupt arbiter.

Detailed behavior is documented in:

```text
docs/rv64imfd/interrupt_system.md
```

---

# RV64 Hardware Timer

The RV64 subsystem includes a dedicated 64-bit bus-accessible timer peripheral.

The timer currently maintains 32-bit internal control and counter registers while exposing a 64-bit MMIO interface.

The register set includes:

```text
0x00 → Control
0x04 → Compare
0x08 → Counter
0x0C → Status
```

The timer provides:

* Enable control
* Compare operation
* Counter operation
* Optional auto-reload
* Interrupt status
* Interrupt generation

The timer interrupt is connected to interrupt source bit 0.

---

# RV64 SoC Wrapper

The RV64 CPU wrapper integrates the processor core with local system peripherals and external memory.

The general architecture is:

```text
                       ┌─────────────────────┐
                       │   RV64IMFD Core     │
                       └──────────┬──────────┘
                                  │
                           64-bit CPU Bus
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        External Memory       Timer            IRQ Arbiter
                                  │                   │
                                  └─────────┬─────────┘
                                            │
                                            ▼
                                           IRQ
```

Local address decoding is performed by the wrapper.

This allows the CPU core to remain separated from the system-level routing of internal peripherals.

---

# RV64 Firmware

A bare-metal GCC firmware environment is provided for RV64IMFD.

The firmware environment contains:

```text
gcc-firmware/
└── rv64imfd/
    ├── boot.S
    ├── main.c
    ├── soc_map.h
    ├── link.ld
    └── compiler.md
```

The firmware is intended primarily for:

* CPU bring-up
* Instruction execution testing
* MMIO verification
* Interrupt testing
* FPU/MDU integration testing
* Simulation
* Future FPGA bring-up

The current firmware also contains example mappings for the planned synthesizer subsystem.

These synthesizer accesses are currently intended as **testbench placeholders** and should not be interpreted as evidence of a completed or FPGA-validated oscillator implementation.

---

# RV64 Firmware Build

The RV64 firmware is compiled using the RISC-V GNU toolchain with:

```text
-march=rv64imfd
-mabi=lp64d
```

The firmware build process is documented in:

```text
gcc-firmware/rv64imfd/compiler.md
```

The build produces:

```text
firmware.elf
firmware.mem
firmware.dump
```

The memory image is intended for use by Verilog/Vivado simulation environments.

---

### Current RV64IMFD Status

| Verification Stage | Status |
|---|---|
| Core-level simulation stress test | **Passed** |
| Integer ALU | **Passed** |
| MDU | **Passed** |
| Memory path | **Passed** |
| Branch path | **Passed** |
| Basic CPU/FPU integration | **Passed** |
| Exhaustive ISA verification | **Pending** |
| Formal verification | **Pending** |
| CPU + FPU FPGA validation | **Pending** |

The simulation result should be interpreted as functional evidence for the tested instruction paths, not as a claim of complete RV64IMFD architectural compliance.

---

## FPU

The project also contains a standalone RV64 floating-point unit supporting the floating-point datapath used by the RV64IMFD processor.

The standalone FPU has been validated on FPGA independently.

This provides hardware-level validation of the FPU itself, while CPU-level FPGA integration remains a separate pending verification stage.

---

# VRM Synthesizer Series

The RV64 memory map and firmware environment intentionally contain an early placeholder for the future **VRM Synthesizer Series**.

The planned series is expected to include hardware such as:

* Digital oscillators
* Wavetable-based waveform generation
* Sub-oscillator modes
* LFO functionality
* Noise generation
* Glide / portamento control
* Additional synthesizer-oriented DSP components

The current repository only establishes the **SoC-level address-space and firmware interface concept**.

The oscillator implementation itself remains under development.

The synthesizer series has **not yet been independently validated on FPGA**, and the current RV64 firmware references to the oscillator region are therefore intended for simulation/testbench use only.

Future synthesizer components will be introduced as their individual implementations become sufficiently mature and independently verified.

---

# Verification

Verification is organized according to CPU architecture.

```text
tb/
├── rv32i/
└── rv64imfd/
```

The RV32I verification environment covers the CPU core and SoC-level integration.

The RV64IMFD verification environment is being developed to cover:

* RV64 integer execution
* Pipeline behavior
* Load/store operations
* Byte write strobes
* Branch and jump handling
* MDU operations
* FPU operations
* Interrupt handling
* Timer operation
* MMIO accesses
* Firmware execution
* CPU/peripheral integration

The RV64IMFD testbench is intended to combine processor-level verification with dedicated FPU verification and MDU testing.

Detailed verification status is documented in:

```text
docs/rv64imfd/verification.md
```

---

# FPGA Verification

## RV32I

The RV32I CPU implementation has been verified on FPGA hardware.

The FPGA validation covers system-level operation including:

* RV32I instruction execution
* ALU operations
* Load/store operations
* Byte-enable support
* Pipeline hazard handling
* Data forwarding
* Branch and jump handling
* WFI behavior
* Interrupt wake-up
* Machine-level interrupt handling
* MRET
* Hardware timer
* Interrupt arbiter
* Memory-mapped I/O

The application-level FPGA design used for validation is not included because its associated research work remains unpublished.

## RV64IMFD

The RV64IMFD CPU is currently **not FPGA-verified**.

Although individual components such as the FPU have undergone independent hardware validation, this should not be interpreted as validation of the complete RV64IMFD CPU subsystem.

The complete RV64IMFD integration still requires:

1. CPU-level simulation verification
2. SoC-level simulation verification
3. Firmware-based verification
4. FPGA synthesis
5. FPGA hardware validation

---

# Documentation

Architecture-specific documentation is maintained under:

```text
docs/
├── rv32i/
└── rv64imfd/
```

The RV64IMFD documentation currently includes:

```text
docs/rv64imfd/
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

The documentation is intended to describe the architecture independently from the RTL implementation.

---

# Design Philosophy

The CPU series follows several design principles.

### Modular

CPU cores, peripherals, memory interfaces, firmware, and verification environments are maintained as separate components.

### Architecture-Oriented

Each CPU architecture has its own RTL, testbench, memory map, firmware, and documentation.

### Synthesis-Oriented

RTL is developed with practical FPGA synthesis and hardware implementation in mind.

### Verification-Driven

New functionality is progressively verified through simulation before hardware validation.

### System-Oriented

The processors are developed as part of a larger SoC architecture rather than as isolated CPU cores.

### Expandable

The architecture is intended to support future integration with:

* DSP accelerators
* Audio processing blocks
* NPU components
* Memory controllers
* Application-specific accelerators
* Additional interrupt sources
* Additional RISC-V processor variants
* Synthesizer and audio-generation hardware

---

# Relation to the VRM21 RTL Ecosystem

This repository is part of the broader **VRM21 RTL development ecosystem**.

The CPU series provides a programmable control and processing layer for future systems integrating custom hardware accelerators and DSP components.

The surrounding VRM21 RTL ecosystem includes reusable hardware blocks such as:

* DSP components
* Memory cores
* FIFO cores
* Audio processing blocks
* Arithmetic components
* Processing accelerators
* Utility RTL
* Floating-point processing components

The RV64IMFD architecture is intended to provide a higher-capability programmable platform for integrating these components through a memory-mapped SoC architecture.

---

# Current Development Scope

The current development scope covers two processor architectures:

### RV32I

The RV32I implementation is the mature baseline of the series and has completed FPGA validation.

### RV64IMFD

The RV64IMFD implementation is the current next-generation architecture under active development.

Current priorities are:

1. RV64IMFD instruction correctness
2. Pipeline verification
3. MDU verification
4. FPU integration verification
5. Interrupt and timer verification
6. Firmware-based testing
7. SoC-level verification
8. FPGA validation
9. Documentation refinement

The planned VRM Synthesizer Series remains a separate development track and is currently represented only through reserved address-space and firmware placeholders.

---

# Future Development

Future versions of the series may introduce:

* Additional RISC-V extensions
* More advanced interrupt architecture
* Additional memory interfaces
* DSP coprocessors
* Audio accelerators
* NPU integration
* Custom SoC interconnects
* VRM Synthesizer hardware
* Additional FPGA validation platforms

The architecture-specific repository structure is intended to accommodate these developments without requiring major restructuring.

---

# License

Licensed under the MIT License.

Provided as-is, without warranty.

---

# Author / Project

**VRM21 Studios**

**VRM21 CPU RISC-V Series**

This repository is part of the ongoing VRM21 hardware and RTL development projects.
