# RV64IMFD Firmware Compilation Guide

This document describes how to build the bare-metal firmware for the **VRM21 RV64IMFD CPU** using the RISC-V GNU toolchain.

## 1. Requirements

The following toolchain is required:

* `riscv64-unknown-elf-gcc`
* `riscv64-unknown-elf-objcopy`
* `riscv64-unknown-elf-objdump`

The firmware is built for the following ISA and ABI:

```text
ISA : RV64IMFD
ABI : LP64D
```

## 2. Firmware Source Files

The firmware build expects the following files:

```text
RV64_Firmware/
├── boot.S
├── link.ld
├── main.c
└── soc_map.h
```

The linker script places the firmware in the SoC's unified RAM starting at address `0x4000`.

## 3. Compilation

Run the following commands from the firmware directory:

```bash
cd /home/al/workspace/firmware_gcc/RV64_Firmware

riscv64-unknown-elf-gcc \
    -march=rv64imfd \
    -mabi=lp64d \
    -O2 \
    -ffreestanding \
    -fno-builtin \
    -nostdlib \
    -fno-delete-null-pointer-checks \
    -Wl,--no-relax \
    -T link.ld \
    boot.S main.c \
    -o firmware.elf
```

### Compiler Options

| Option                            | Purpose                                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------------------- |
| `-march=rv64imfd`                 | Target the RV64IMFD instruction set                                                             |
| `-mabi=lp64d`                     | Use the 64-bit integer ABI with double-precision floating-point support                         |
| `-O2`                             | Enable compiler optimization suitable for firmware builds                                       |
| `-ffreestanding`                  | Build for a freestanding environment without assuming a hosted C runtime                        |
| `-fno-builtin`                    | Disable implicit compiler assumptions about standard library built-ins                          |
| `-nostdlib`                       | Do not link against the standard C library or default startup files                             |
| `-fno-delete-null-pointer-checks` | Preserve explicit null-pointer checks                                                           |
| `-Wl,--no-relax`                  | Disable linker relaxation to keep generated code compatible with the current CPU implementation |
| `-T link.ld`                      | Use the project-specific linker script                                                          |

## 4. Generate Memory Initialization File

After compilation, convert the ELF image into a Verilog-compatible memory initialization file:

```bash
riscv64-unknown-elf-objcopy \
    -O verilog \
    --change-addresses -0x4000 \
    firmware.elf \
    firmware.mem
```

The address adjustment maps the firmware image relative to the SoC RAM base address used by the testbench.

The resulting file is:

```text
firmware.mem
```

This file can be loaded by the Verilog/SystemVerilog testbench as the processor's firmware image.

## 5. Generate Disassembly

Generate a complete disassembly of the ELF image for debugging and inspection:

```bash
riscv64-unknown-elf-objdump -D firmware.elf > firmware.dump
```

This produces:

```text
firmware.dump
```

The dump is useful for verifying:

* Generated instruction sequences
* Reset and interrupt vector placement
* Function addresses
* Compiler-generated control flow
* RV64IMFD instruction usage
* Firmware-to-hardware integration

## 6. Complete Build Script

For convenience, the complete build sequence can be placed in a shell script:

```bash
clear

echo "Building RV64IMFD Firmware..."

cd /home/al/workspace/firmware_gcc/RV64_Firmware

riscv64-unknown-elf-gcc \
    -march=rv64imfd \
    -mabi=lp64d \
    -O2 \
    -ffreestanding \
    -fno-builtin \
    -nostdlib \
    -fno-delete-null-pointer-checks \
    -Wl,--no-relax \
    -T link.ld \
    boot.S main.c \
    -o firmware.elf

riscv64-unknown-elf-objcopy \
    -O verilog \
    --change-addresses -0x4000 \
    firmware.elf \
    firmware.mem

riscv64-unknown-elf-objdump \
    -D firmware.elf \
    > firmware.dump

echo "Build completed successfully."
```

## 7. Build Outputs

A successful build produces the following files:

```text
RV64_Firmware/
├── firmware.elf
├── firmware.mem
└── firmware.dump
```

### `firmware.elf`

The ELF executable containing the linked RV64IMFD firmware image.

### `firmware.mem`

A Verilog-compatible memory initialization image intended for simulation and testbench use.

### `firmware.dump`

A human-readable disassembly of the generated firmware image.

## 8. Current Firmware Scope

The current firmware is primarily intended for **simulation and testbench validation of the RV64IMFD SoC integration**.

The synthesizer-related MMIO definitions are retained as a placeholder for the planned **VRM Synthesizer Series**. The synthesizer hardware is still under development and is not considered independently FPGA-validated at this stage.
