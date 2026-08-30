# RV64IMFD Firmware

This directory contains the bare-metal firmware used to exercise and validate the **VRM21 RV64IMFD CPU** and its system-level interfaces in simulation.

The firmware provides the startup sequence, linker configuration, memory-mapped peripheral definitions, interrupt handler, and C test program required by the current RV64IMFD testbench environment.

## Current Status

The **RV64IMFD CPU and its integrated M/D/F extensions are currently under development and validation**.

This firmware is currently intended primarily for **simulation and testbench use**. FPGA validation of the complete RV64IMFD system is planned separately.

## VRM Synthesizer Interface

The firmware currently includes memory-mapped register definitions and test sequences for a planned **VRM Synthesizer Series**.

The synthesizer-related interface is intentionally retained in this firmware as a **placeholder** for future hardware integration. It should not be interpreted as an indication that the synthesizer hardware is already part of the validated RV64IMFD implementation.

The current placeholder interface includes functionality intended for future oscillator and synthesizer development, including:

* Oscillator phase increment control
* Amplitude control
* Generator mode selection
* LFO configuration
* Wavetable selection
* Portamento / glide control
* AXI-Stream packet sizing

The corresponding MMIO definitions can be found in:

```text
soc_map.h
```

and the corresponding address map is defined by the SoC memory-map headers.

## VRM Synthesizer Series Status

The **VRM Synthesizer Series**, including the planned oscillator hardware, is currently **under development**.

At the current stage:

* The synthesizer hardware is not yet considered complete.
* The oscillator has not yet been independently validated on FPGA.
* The synthesizer interface in this firmware is therefore treated as a development placeholder.
* The current firmware sequence is intended for simulation/testbench stimulus and future integration testing.
* Independent FPGA validation of the synthesizer hardware will be performed once the corresponding hardware implementation is sufficiently mature.

This separation is intentional so that the RV64IMFD CPU development can proceed independently from the synthesizer development.

## Firmware Structure

```text
RV64_Firmware/
├── boot.S
├── link.ld
├── main.c
├── soc_map.h
├── compiler.md
└── README.md
```

### `boot.S`

Provides the processor startup sequence, reset vector, interrupt vector, stack initialization, and entry into the C firmware.

### `link.ld`

Defines the firmware memory layout and places the program into the SoC's unified RAM region.

### `soc_map.h`

Defines the memory-mapped system peripherals and the current placeholder interface for the planned VRM Synthesizer Series.

### `main.c`

Contains the bare-metal firmware entry point, system initialization, interrupt handler, and current simulation/testbench stimulus.

### `compiler.md`

Provides the build instructions for generating the ELF, Verilog memory image, and disassembly.

## Important Note

The synthesizer-related code is retained here as a **forward-looking integration placeholder**.

Its presence does not represent completed synthesizer hardware or FPGA validation. Future revisions of the VRM Synthesizer Series may introduce changes to the register map, hardware interface, firmware interface, or test sequence.

The firmware should therefore be considered a **development and simulation artifact** until the corresponding hardware implementation and independent FPGA validation are completed.
