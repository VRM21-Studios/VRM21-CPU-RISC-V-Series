# VRM21 CPU RISC-V Series

A collection of custom RISC-V processor cores and supporting hardware developed as part of the **VRM21 Hardware/RTL Series**.

This repository focuses on the development of custom RISC-V CPU cores, their surrounding system components, verification environments, firmware support, and SoC-level integration.

The current implementation provides an **RV32I CPU core and a minimal RV32I-based SoC subsystem**, including interrupt handling, a hardware timer, an interrupt arbiter, memory-mapped peripherals, and GCC-based firmware support.

Future versions of the series are planned to include **RV64IMFD** and additional processor-related components.

---

## Repository Status

| Component                        | Status                          |
| -------------------------------- | ------------------------------- |
| RV32I CPU Core                   | Available                       |
| RV32I Pipeline                   | Available                       |
| RV32I ALU                        | Available                       |
| Load/Store Unit                  | Available                       |
| Byte Enable Support              | Available                       |
| Load/Store Hazard Handling       | Available                       |
| Data Forwarding                  | Available                       |
| Branch / Jump Handling           | Available                       |
| WFI Support                      | Available                       |
| Machine Return (`MRET`)          | Available                       |
| Basic Machine Interrupt Handling | Available                       |
| Hardware Timer                   | Available                       |
| Interrupt Arbiter                | Available                       |
| Memory-Mapped SoC Wrapper        | Available                       |
| RV32I Firmware                   | Available                       |
| Simulation Testbench             | Available                       |
| Vivado Simulation Verification   | Available                       |
| RV32I FPGA Verification          | Verified                        |
| RV64IMFD                         | Planned / Not Yet FPGA Verified |

> **Note:** The current repository structure intentionally separates each CPU architecture under its own `rv32i/` directory. This allows future architectures such as `rv64imfd/` to be added without restructuring the repository.

---

# Architecture Overview

The current CPU subsystem is organized around the following hierarchy:

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
│       ├── tb_vrm_cpu_rv32i_core.v
│       ├── tb_vrm_cpu_wrapper.v
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
│       ├── ...
│       └── 06_tb_result.md
│
├── .github/
│   └── workflows/
│       └── rv32i/
│           └── ...
│
└── README.md
```

The architecture-specific directory layout is intentional.

Each supported CPU architecture has its own implementation, verification environment, memory map, firmware, documentation, and CI configuration.

For example, the planned structure will allow:

```text
rtl/
├── rv32i/
└── rv64imfd/

tb/
├── rv32i/
└── rv64imfd/

include/
├── rv32i/
└── rv64imfd/

gcc-firmware/
├── rv32i/
└── rv64imfd/

docs/
├── rv32i/
└── rv64imfd/
```

This prevents architecture-specific files from becoming mixed together as the CPU series grows.

---

# RV32I CPU

The current processor implementation is based on the **RISC-V RV32I base integer instruction set**.

The CPU uses a pipelined architecture with dedicated stages for:

```text
IF → ID → EX → MEM → WB
```

where:

* **IF** — Instruction Fetch
* **ID** — Instruction Decode and Register Read
* **EX** — Execute, Branch, Jump and Forwarding
* **MEM** — Memory Access
* **WB** — Writeback

The implementation includes hardware mechanisms for handling common pipeline dependencies and control-flow changes.

---

## Supported Instruction Groups

The current RV32I implementation covers the following instruction groups:

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

The current implementation also provides support for:

* `WFI`
* `MRET`

Interrupt handling is implemented as a lightweight custom machine-level mechanism around these instructions.

---

# Pipeline and Hazard Handling

The CPU contains both **data forwarding** and **load-use hazard detection**.

## Data Forwarding

Results from later pipeline stages can be forwarded directly into the execute stage.

The forwarding paths include:

```text
EX/MEM → EX
MEM/WB → EX
```

This reduces unnecessary pipeline stalls for normal ALU dependencies.

For example:

```text
ADD  x3, x1, x2
SUB  x4, x3, x1
```

The second instruction can obtain the newly generated `x3` through forwarding rather than waiting for the register file writeback.

---

## Load-Use Hazard

A load instruction has an additional dependency because its data becomes available later in the pipeline.

The CPU therefore detects a condition such as:

```text
LW   x14, 0(x13)
ADDI x15, x14, 1
```

and inserts a pipeline stall when the following instruction immediately consumes the loaded register.

This prevents the consumer instruction from operating on stale data.

---

# Branch and Jump Handling

Branches and jumps are resolved in the execute stage.

When a control-flow instruction is taken:

```text
branch_taken_ex
```

causes the program counter to switch to the calculated target address.

The corresponding younger instruction in the pipeline is invalidated through:

```text
flush_ex
```

This prevents instructions fetched from the wrong sequential path from being committed.

The implementation supports:

* Conditional branches
* `JAL`
* `JALR`
* `MRET`

---

# Interrupt Architecture

The RV32I subsystem provides a lightweight interrupt architecture consisting of:

```text
Interrupt Sources
       │
       ▼
┌──────────────────┐
│ Interrupt Arbiter│
└────────┬─────────┘
         │
         ▼
       CPU IRQ
         │
         ▼
      ISR Vector
         │
         ▼
       MRET
```

The interrupt arbiter maintains:

* Pending interrupt state
* Interrupt enable mask
* Rising-edge detection
* Write-one-to-clear functionality

The current system reserves:

```text
Bit 0      → Hardware Timer
Bit 1-31   → External / Future Interrupt Sources
```

This provides a simple mechanism for expanding the interrupt architecture without changing the CPU core interface.

---

# Hardware Timer

The SoC wrapper contains a memory-mapped hardware timer.

The timer provides:

* Enable control
* Auto-reload mode
* Compare value
* Counter register
* Interrupt pending status
* Interrupt enable
* Write-one-to-clear status handling

The timer is connected to the interrupt arbiter as:

```text
Timer
  │
  ▼
IRQ Source Bit 0
  │
  ▼
Interrupt Arbiter
  │
  ▼
CPU
```

The timer therefore provides a basic hardware-driven interrupt source for software and system-level verification.

---

# Memory-Mapped System

The current RV32I system uses the following memory map:

|          Address |     Size | Peripheral                       |
| ---------------: | -------: | -------------------------------- |
|    `0x0000_0000` | `0x1000` | RAM                              |
|    `0x0000_1000` | `0x0100` | Hardware Timer                   |
|    `0x0000_2000` | `0x0100` | Interrupt Arbiter                |
| Higher addresses |        — | Reserved for future accelerators |

The architecture is intentionally designed around a **system-first memory map**, allowing future DSP, accelerator, and peripheral blocks to be mapped above the system-core region.

---

# RV32I SoC Wrapper

The CPU core itself is kept relatively independent from the surrounding SoC infrastructure.

The wrapper integrates:

```text
                   ┌─────────────────────┐
                   │   RV32I CPU Core    │
                   └──────────┬──────────┘
                              │
                       CPU Data Bus
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
        External RAM       Timer       IRQ Arbiter
                              │               │
                              └───────┬───────┘
                                      │
                                      ▼
                                     IRQ
```

The wrapper performs local address decoding and routes accesses either to:

* External memory
* Hardware timer
* Interrupt arbiter

This keeps peripheral-specific address decoding outside the CPU core.

---

# Byte-Enable Support

The RV32I CPU provides four byte-enable signals:

```text
mem_be[3:0]
```

These signals allow byte- and halfword-level stores while maintaining a 32-bit data interface.

For example:

```text
SB
```

activates one byte lane, while:

```text
SH
```

activates two adjacent byte lanes.

`SW` activates all four lanes.

This mechanism is useful for:

* BRAM interfaces
* MMIO registers
* Memory systems
* Future SoC interconnects

---

# Load Data Extraction

For load operations, the CPU uses the address offset to select the appropriate byte or halfword from the returned 32-bit memory word.

The implementation supports:

```text
LB
LH
LW
LBU
LHU
```

with both sign extension and zero extension as required by the RV32I specification.

---

# WFI and CPU Halt

The CPU implements a lightweight `WFI` mechanism.

When `WFI` reaches the appropriate pipeline stage, the CPU asserts:

```text
cpu_halt
```

The CPU then waits for an interrupt.

When an interrupt arrives:

```text
IRQ
 │
 ▼
Wake CPU
 │
 ▼
Jump to interrupt vector
 │
 ▼
Execute ISR
 │
 ▼
MRET
 │
 ▼
Resume execution
```

This functionality is verified in both the standalone CPU testbench and the SoC wrapper integration testbench.

---

# Firmware Support

The repository includes a small bare-metal firmware environment for RV32I.

The firmware is designed for:

* CPU bring-up
* SoC integration testing
* MMIO verification
* Interrupt testing
* Simulation
* Future FPGA bring-up

The firmware is built using the RISC-V GNU toolchain.

The current firmware structure is:

```text
gcc-firmware/
└── rv32i/
    ├── boot.S
    ├── main.c
    ├── soc_map.h
    ├── link.ld
    └── build.sh
```

---

# Boot Flow

The RV32I firmware starts from the reset vector:

```text
0x00000000
```

The interrupt vector is located at:

```text
0x00000004
```

The general flow is:

```text
Reset
  │
  ▼
_start
  │
  ├── Reset handler
  │
  └── main()
        │
        ├── Peripheral initialization
        ├── Timer configuration
        ├── IRQ configuration
        └── Test / application code
```

The linker script places the firmware into the 4 KB RAM region currently defined for the RV32I system.

---

# Firmware Build

The firmware can be built using the RISC-V GNU toolchain.

From the RV32I firmware directory:

```bash
./build.sh
```

or manually:

```bash
riscv64-unknown-elf-gcc \
    -march=rv32i \
    -mabi=ilp32 \
    -O2 \
    -ffreestanding \
    -fno-builtin \
    -nostdlib \
    -T link.ld \
    boot.S main.c \
    -o firmware.elf
```

The generated ELF image can then be converted into a Verilog memory image:

```bash
riscv64-unknown-elf-objcopy \
    -O verilog \
    firmware.elf \
    firmware.mem
```

A disassembly file can also be generated:

```bash
riscv64-unknown-elf-objdump \
    -D firmware.elf \
    > firmware.dump
```

The resulting files are:

```text
firmware.elf
firmware.mem
firmware.dump
```

`firmware.mem` is intended for loading into a Verilog/Vivado memory model, while `firmware.dump` is useful for instruction-level debugging.

---

# Verification

The RV32I implementation includes dedicated simulation testbenches.

The verification environment is divided into:

```text
tb/
└── rv32i/
```

Two major verification levels are currently provided.

## CPU Core Verification

The standalone CPU testbench verifies:

* ALU operations
* Immediate operations
* Register operations
* LUI / AUIPC behavior
* Load / store operations
* Byte enables
* Byte and halfword extraction
* Load-use hazards
* Data forwarding
* Branch flushing
* `WFI`
* Interrupt wake-up
* `MRET`

## SoC Wrapper Verification

The wrapper-level testbench verifies integration between:

* RV32I CPU
* External memory
* Hardware timer
* Interrupt arbiter
* MMIO address decoder
* Interrupt service routine

The testbench also verifies that the CPU can:

1. Configure the timer.
2. Enable the timer interrupt.
3. Enter `WFI`.
4. Receive the timer interrupt.
5. Enter the interrupt service routine.
6. Clear the interrupt sources.
7. Return through `MRET`.
8. Resume normal execution.

---

# Testbench Results

Detailed expected simulation output and verification results are documented under:

```text
docs/rv32i/
```

The testbench documentation is intended to provide a reproducible reference for the expected Vivado simulator console output.

A successful simulation should report passing results for the tested CPU and SoC integration features.

---

# Documentation

Architecture-specific documentation is stored separately from the RTL source.

Current documentation follows the same architecture hierarchy:

```text
docs/
└── rv32i/
    ├── ...
    └── 06_tb_result.md
```

The documentation covers areas such as:

* CPU architecture
* Pipeline organization
* Instruction support
* Memory interface
* Interrupt architecture
* Timer
* SoC integration
* Firmware
* Verification
* Testbench results

Additional documentation will be added as the CPU series develops.

---

# GitHub Actions / CI

Continuous integration configuration is also separated by CPU architecture.

Current structure:

```text
.github/
└── workflows/
    └── rv32i/
        └── ...
```

This allows future architectures to introduce independent verification workflows without coupling them to the RV32I implementation.

The intended structure is:

```text
.github/workflows/
├── rv32i/
└── rv64imfd/
```

when the RV64IMFD implementation becomes sufficiently mature.

---

## FPGA Verification

### RV32I
The RV32I CPU implementation has been verified on FPGA hardware.

The FPGA verification covers the core CPU pipeline and its associated system-level components, including:

- RV32I instruction execution
- ALU operations
- Load/store operations with byte-enable support
- Pipeline hazard handling and forwarding
- Branch and jump handling
- WFI and interrupt wake-up behavior
- Machine-mode interrupt handling and MRET
- Hardware timer
- Interrupt arbiter
- Memory-mapped I/O integration

### RV64IMFD
The RV64IMFD implementation is currently under development and has **not yet been FPGA-verified**.

Its RTL is maintained separately within the CPU Series architecture and will be verified on FPGA in a subsequent development stage.

---

# Future RV64IMFD Series

The next major CPU target is:

```text
RV64IMFD
```

covering:

* RV64I
* M — Integer Multiplication and Division
* F — Single-Precision Floating Point
* D — Double-Precision Floating Point

The planned architecture will be introduced under separate architecture-specific directories rather than modifying the RV32I directory structure.

For example:

```text
rtl/
├── rv32i/
└── rv64imfd/

tb/
├── rv32i/
└── rv64imfd/

include/
├── rv32i/
└── rv64imfd/

gcc-firmware/
├── rv32i/
└── rv64imfd/

docs/
├── rv32i/
└── rv64imfd/
```

The RV64IMFD implementation should be considered **development-stage hardware** until its verification and FPGA validation are completed.

---

# Design Philosophy

The CPU series follows several design principles:

### Modular

CPU, peripherals, memory interfaces, firmware, and verification environments are separated into reusable components.

### Parameterized Where Appropriate

Hardware components are designed with reuse and future integration in mind.

### Synthesis-Oriented

RTL is written with FPGA synthesis and practical hardware implementation in mind.

### Verification-Driven

New functionality is accompanied by simulation-level verification before being considered mature.

### System-Oriented

The CPU is developed as part of a larger SoC architecture rather than as an isolated processor core.

### Expandable

The architecture is intended to support future integration with:

* DSP accelerators
* Audio processing blocks
* NPU components
* Memory controllers
* Application-specific accelerators
* Additional interrupt sources
* Additional RISC-V CPU variants

---

# Relation to the VRM21 RTL Ecosystem

This repository is part of the broader **VRM21 RTL development ecosystem**.

The CPU series is intended to serve as a processing/control element for future hardware systems, including systems that integrate custom DSP and accelerator modules.

The surrounding VRM21 RTL ecosystem includes reusable hardware blocks such as:

* DSP components
* Memory cores
* FIFO cores
* Audio processing blocks
* Arithmetic components
* Processing accelerators
* Utility RTL

The CPU series provides a programmable control layer that can eventually coordinate these hardware components through a memory-mapped SoC architecture.

---

# Current Development Scope

The current focus is the RV32I implementation.

Development priorities are currently centered around:

1. RV32I CPU correctness
2. Pipeline verification
3. Interrupt and timer integration
4. Firmware-based system testing
5. SoC-level verification
6. FPGA validation
7. Documentation
8. Preparation for the RV64IMFD branch of the series

The repository structure is intentionally prepared for the next CPU architecture without requiring a major reorganization.

---

# License

See the repository license file for the applicable licensing terms.

---

# Author / Project

**VRM21 Studios**

VRM21 CPU RISC-V Series

This repository is part of the ongoing VRM21 hardware and RTL development projects.
