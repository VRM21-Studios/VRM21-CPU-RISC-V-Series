# VRM21 CPU RISC-V Series

A collection of custom RISC-V processor cores and supporting hardware developed as part of the **VRM21 Hardware/RTL Series**.

This repository focuses on the development of custom RISC-V CPU cores, their surrounding system components, verification environments, firmware support, and SoC-level integration.

The repository currently contains an **RV32I CPU subsystem** together with supporting interrupt, timer, memory-mapped I/O, firmware, and verification infrastructure.

---

## Motivation

This project was developed as part of a self-directed study of computer architecture through practical RTL implementation.

Rather than studying processor architecture only from an ISA or software perspective, the project explores how instructions are decoded, executed, and moved through an actual hardware datapath. The RISC-V architecture provides an accessible and open foundation for studying concepts such as pipelining, hazard handling, memory interfaces, control logic, and processor state.

The primary objective of the project is therefore educational: to develop a deeper understanding of how a processor works by implementing and examining its architecture at the RTL level.

---

## Repository Status

| Component                     | Status            |
| ----------------------------- | ----------------- |
| RV32I CPU Core                | Available         |
| RV32I Pipeline                | Available         |
| RV32I ALU                     | Available         |
| RV32I Load/Store Unit         | Available         |
| RV32I Byte Enable Support     | Available         |
| RV32I Hazard Handling         | Available         |
| RV32I Data Forwarding         | Available         |
| RV32I Branch / Jump Handling  | Available         |
| RV32I WFI Support             | Available         |
| RV32I MRET Support            | Available         |
| RV32I Interrupt Handling      | Available         |
| RV32I Hardware Timer          | Available         |
| RV32I Interrupt Arbiter       | Available         |
| RV32I SoC Wrapper             | Available         |
| RV32I Firmware                | Available         |
| RV32I Simulation Verification | Available         |
| RV32I FPGA Verification       | Verified          |
| VRM Synthesizer Series        | Under Development |

> **FPGA Verification Note:** The RV32I implementation has been verified on FPGA as part of a system-level hardware integration. The specific application-level design used during FPGA validation is not included in this repository because its associated research work is currently unpublished.

> **Synthesizer Development Note:** The memory map and firmware environment contain a reserved/example region for the planned VRM Synthesizer Series. The oscillator-related interface is currently used only as a placeholder for future SoC integration and firmware testbench development. The synthesizer/oscillator implementation is not considered a completed or FPGA-validated component.

---

# Architecture Overview

The repository is organized by CPU architecture:

```text
VRM21-CPU-RISC-V-Series
│
├── rtl/
│   └── rv32i/
│       ├── vrm_cpu_rv32i_core.v
│       ├── vrm_cpu_rv32i_wrapper.v
│       ├── vrm_irq_arbiter.v
│       ├── vrm_timer.v
│       └── ...
│
├── tb/
│   └── rv32i/
│       ├── tb_vrm_cpu_rv32i_core.sv
│       ├── tb_vrm_cpu_wrapper.sv
│       └── ...
│
├── include/
│   └── rv32i/
│       └── vrm_soc_map_rv32i.vh
│
├── gcc-firmware/
│   └── rv32i/
│       ├── boot.S
│       ├── main.c
│       ├── soc_map.h
│       ├── link.ld
│       └── build.sh
│
├── docs/
│   └── rv32i/
│       └── ...
│
└── README.md
```

The architecture-specific directory layout is intentional.

The RV32I architecture has its own implementation, verification environment, memory map, firmware, and documentation.

This allows future architectures to be introduced without mixing architecture-specific RTL and verification infrastructure.

---

# RV32I CPU

The RV32I processor is the primary CPU implementation in the series and provides a 32-bit RISC-V integer processing subsystem.

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

# RV32I Memory System

The RV32I system provides the processor with a memory interface suitable for integration into FPGA-based SoC designs.

The CPU subsystem supports:

* Instruction fetch
* Data load/store operations
* Byte-enable generation
* Memory-mapped peripherals
* External memory integration

The memory interface is designed to keep the processor core separated from the surrounding SoC interconnect and memory implementation.

---

# RV32I Memory Map

The current RV32I system defines the following architectural regions:

| Address Range               | Region | Description                                |
| --------------------------- | ------ | ------------------------------------------ |
| `0x0000_0000 - 0x0000_00FF` | Tier 0 | Hardware Timer                             |
| `0x0000_1000 - 0x0000_10FF` | Tier 0 | Interrupt Arbiter                          |
| `0x0000_4000 - 0x0000_7FFF` | Tier 1 | Main Data Memory                           |
| `0x4000_0000 - 0x4000_0FFF` | Tier 2 | Reserved Application / Accelerator  Region |

The Tier 2 region is reserved for future application-specific hardware.

The memory map is intentionally extensible so that additional peripherals and accelerators can be introduced without restructuring the CPU architecture.

---

# Interrupt Architecture

The RV32I system includes a dedicated interrupt subsystem.

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

The external interrupt inputs are synchronized through a two-stage flip-flop structure before entering the interrupt arbiter.

---

# RV32I Hardware Timer

The RV32I subsystem includes a bus-accessible hardware timer peripheral.

The timer provides:

* Enable control
* Compare operation
* Counter operation
* Optional auto-reload
* Interrupt status
* Interrupt generation

The timer interrupt is connected to the interrupt arbiter.

---

# RV32I SoC Wrapper

The RV32I CPU wrapper integrates the processor core with local system peripherals and external memory.

The general architecture is:

```text
                       ┌─────────────────────┐
                       │     RV32I Core      │
                       └──────────┬──────────┘
                                  │
                            CPU Memory Bus
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

This keeps the CPU core separated from the system-level routing of internal peripherals.

---

# RV32I Firmware

A bare-metal GCC firmware environment is provided for RV32I.

The firmware environment contains:

```text
gcc-firmware/
└── rv32i/
    ├── boot.S
    ├── main.c
    ├── soc_map.h
    ├── link.ld
    └── build.sh
```

The firmware is intended primarily for:

* CPU bring-up
* Instruction execution testing
* MMIO verification
* Interrupt testing
* Simulation
* FPGA bring-up

---

# RV32I Firmware Build

The firmware is compiled using the RISC-V GNU toolchain for the RV32I architecture.

The build process is documented in:

```text
gcc-firmware/rv32i/
```

The build produces memory images suitable for use by simulation and FPGA development environments.

---

## RV32I Verification Status

| Verification Stage       | Status   |
| ------------------------ | -------- |
| Core-level simulation    | Passed   |
| Integer ALU              | Passed   |
| Load/store operations    | Passed   |
| Byte-enable support      | Passed   |
| Branch and jump handling | Passed   |
| Pipeline hazard handling | Passed   |
| Data forwarding          | Passed   |
| Interrupt handling       | Passed   |
| Hardware timer           | Passed   |
| Interrupt arbiter        | Passed   |
| SoC integration          | Passed   |
| FPGA validation          | Verified |

The verification status refers to the tested instruction paths and system-level hardware configuration. It should not be interpreted as a claim of exhaustive formal verification or complete architectural compliance.

---

# FPGA Verification

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

---

# VRM Synthesizer Series

The RV32I memory map and firmware environment intentionally contain an early placeholder for the future **VRM Synthesizer Series**.

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

The synthesizer series has **not yet been independently validated on FPGA**, and any references to the reserved oscillator region are therefore intended for simulation or future integration use only.

Future synthesizer components will be introduced as their individual implementations become sufficiently mature and independently verified.

---

# Verification

Verification is organized according to CPU architecture.

```text
tb/
└── rv32i/
```

The RV32I verification environment covers the CPU core and SoC-level integration.

Verification includes:

* RV32I instruction execution
* Pipeline behavior
* Load/store operations
* Byte write enables
* Branch and jump handling
* Hazard handling
* Data forwarding
* Interrupt handling
* Timer operation
* MMIO accesses
* Firmware execution
* CPU/peripheral integration

The verification environment is intended to combine processor-level simulation with system-level hardware validation.

---

# Documentation

Architecture-specific documentation is maintained under:

```text
docs/
└── rv32i/
```

Documentation is intended to describe the architecture independently from the RTL implementation.

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

The processor is developed as part of a larger SoC architecture rather than as an isolated CPU core.

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

The CPU architecture is intended to provide a programmable platform for integrating these components through a memory-mapped SoC architecture.

---

# Current Development Scope

The current development scope is centered on the **RV32I processor architecture**.

The RV32I implementation represents the mature baseline of the series and has completed FPGA validation.

Current priorities include:

1. Maintaining RV32I architectural correctness
2. Improving verification coverage
3. Refining documentation
4. Improving firmware examples
5. Expanding SoC-level integration
6. Developing additional FPGA validation platforms
7. Integrating future application-specific hardware

The planned VRM Synthesizer Series remains a separate development track and is currently represented only through reserved address-space and firmware placeholders.

---

# Future Development

Future versions of the series may introduce:

* Additional RISC-V extensions
* Additional RISC-V processor variants
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
