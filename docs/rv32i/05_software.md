# VRM RV32I CPU — Software and Firmware

## 1. Overview

The repository includes a bare-metal firmware flow for the RV32I processor.

The firmware is compiled using a RISC-V GNU toolchain and linked directly into the processor's 4 KB system RAM.

The software environment does not depend on an operating system or standard runtime.

The intended toolchain configuration is:

```text
Architecture : RV32I
ABI          : ILP32
Runtime      : Bare metal
```

---

## 2. Source Files

The firmware consists of:

```text
boot.S
main.c
soc_map.h
link.ld
```

---

## 3. Boot Assembly

The boot code is contained in:

```text
boot.S
```

The entry point is:

```asm
_start:
```

The reset vector is located at:

```text
0x00000000
```

The interrupt vector is located at:

```text
0x00000004
```

The basic startup flow is:

```text
Reset
  |
  v
_start
  |
  +--> reset_handler
  |
  +--> initialize stack
  |
  +--> call main()
  |
  +--> halt / WFI
```

---

## 4. Reset Vector

The reset vector performs an unconditional jump to the reset handler.

Conceptually:

```asm
_start:
    j reset_handler
```

This keeps the vector location separate from the main startup routine.

---

## 5. Interrupt Vector

The interrupt vector is placed immediately after the reset vector.

The vector branches to the timer interrupt service routine.

The firmware uses the compiler's machine-mode interrupt function attribute for the ISR.

The resulting interrupt return sequence is expected to use:

```asm
mret
```

---

## 6. Stack Initialization

The linker script defines:

```text
_stack_top = ORIGIN(RAM) + LENGTH(RAM)
```

For the current memory configuration:

```text
RAM origin = 0x00000000
RAM size   = 0x00001000
```

therefore:

```text
_stack_top = 0x00001000
```

The startup code initializes:

```text
sp = _stack_top
```

before entering `main()`.

---

## 7. Linker Script

The linker script is:

```text
link.ld
```

The memory definition is:

```text
RAM (rwx) :
    ORIGIN = 0x00000000
    LENGTH = 0x1000
```

The following sections are placed into system RAM:

```text
.text
.rodata
.data
.bss
```

This allows the generated firmware image to operate entirely within the 4 KB RAM region.

---

## 8. Software Memory Map

The software header is:

```text
soc_map.h
```

It defines volatile MMIO registers for:

### Timer

```c
TIMER_CTRL
TIMER_COMPARE
TIMER_COUNTER
TIMER_STATUS
```

### Interrupt Arbiter

```c
IRQ_PENDING
IRQ_ENABLE
IRQ_CLEAR
```

The definitions correspond to the hardware memory map implemented by:

```text
vrm_soc_map_rv32i.vh
```

---

## 9. Volatile MMIO Access

Hardware registers are declared using:

```c
volatile uint32_t
```

This prevents the compiler from optimizing away hardware accesses.

For example:

```c
TIMER_CTRL = 0;
```

must result in an actual memory-mapped write.

---

## 10. Interrupt Service Routine

The timer ISR is declared using:

```c
void __attribute__((interrupt("machine"))) timer_isr(void)
```

The current ISR clears the timer status:

```c
TIMER_STATUS = 0;
```

The ISR exists to provide a valid machine-mode interrupt handler for the processor's interrupt vector.

---

## 11. CPU Initialization

The firmware provides:

```c
init_vrm_cpu_pipeline()
```

This function disables system interrupts and timer activity before the main application begins.

The initialization sequence is:

```c
TIMER_CTRL = 0;
IRQ_ENABLE = 0;
IRQ_CLEAR = 0xFFFFFFFF;
```

This ensures that stale peripheral state does not unexpectedly interrupt the initial software execution.

---

## 12. Completion Signaling

The firmware provides:

```c
SIGNAL_DONE()
```

which expands to:

```asm
ebreak
```

This instruction can be used as a software-visible completion marker for simulation environments.

The mechanism is primarily intended for testbench-driven firmware execution.

Note that `EBREAK` is a RISC-V instruction but is not implemented as a normal instruction in the current RV32I RTL core. Therefore, software using this marker should only be executed in an environment that explicitly handles the generated trap or uses the instruction as a simulation/debug marker.

---

## 13. Main Program

The current `main()` performs:

1. System initialization
2. Peripheral shutdown
3. Completion signaling
4. Infinite fallback loop

The structure is intentionally minimal and is suitable as a firmware bring-up example.

---

## 14. Compiler Configuration

The processor must be compiled using:

```text
-march=rv32i
```

and:

```text
-mabi=ilp32
```

The recommended optimization level is:

```text
-O2
```

The firmware is freestanding and therefore uses:

```text
-ffreestanding
-fno-builtin
-nostdlib
```

No operating-system runtime is required.

---

## 15. Build Requirements

The build requires a RISC-V GNU toolchain providing:

```text
riscv64-unknown-elf-gcc
riscv64-unknown-elf-objcopy
riscv64-unknown-elf-objdump
```

The toolchain must support RV32 code generation.

---

## 16. Firmware Build

From the firmware directory:

```bash
cd /path/to/files

echo "Building RV32I firmware..."

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

The resulting ELF file is:

```text
firmware.elf
```

---

## 17. Generate Verilog Memory Image

Vivado simulation environments can use a Verilog-compatible memory image.

Generate the image with:

```bash
riscv64-unknown-elf-objcopy \
    -O verilog \
    firmware.elf \
    firmware.mem
```

Output:

```text
firmware.mem
```

This file is intended to be loaded into the instruction/data memory model used by the simulation environment.

---

## 18. Generate Disassembly

For debugging, generate a disassembly listing:

```bash
riscv64-unknown-elf-objdump \
    -D \
    firmware.elf \
    > firmware.dump
```

Output:

```text
firmware.dump
```

The dump can be used to inspect:

* Generated instructions
* Function addresses
* Branch targets
* Immediate values
* ISR placement
* Stack initialization
* Linker placement

---

## 19. Recommended Build Script

A simple build script can be written as:

```bash
#!/usr/bin/env bash

set -e

echo "Building VRM RV32I firmware..."

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

riscv64-unknown-elf-objcopy \
    -O verilog \
    firmware.elf \
    firmware.mem

riscv64-unknown-elf-objdump \
    -D \
    firmware.elf \
    > firmware.dump

echo ""
echo "Build completed successfully."
echo "  firmware.elf  : ELF executable"
echo "  firmware.mem  : Verilog memory image"
echo "  firmware.dump : Disassembly listing"
```

---

## 20. Firmware Outputs

The build generates three primary artifacts.

| File            | Purpose                                 |
| --------------- | --------------------------------------- |
| `firmware.elf`  | Linked executable and debug information |
| `firmware.mem`  | Verilog memory image                    |
| `firmware.dump` | Human-readable disassembly              |

---

## 21. Firmware and RTL Consistency

The following hardware and software definitions must remain synchronized:

```text
vrm_soc_map_rv32i.vh
        |
        +---- Hardware address decoder
        |
        +---- Timer address definitions
        |
        +---- IRQ arbiter address definitions

soc_map.h
        |
        +---- Software MMIO definitions
```

When a peripheral address changes, both files must be updated.

---

## 22. Current Firmware Scope

The included firmware is a minimal bring-up and integration example.

It is not intended to provide:

* An operating system
* A C standard library
* A scheduler
* A device-driver framework
* Dynamic memory allocation
* Full privileged software support

The purpose is to demonstrate that the CPU can execute compiled RV32I software and interact with its MMIO peripherals.

---

## 23. Future Software Expansion

The firmware infrastructure can later be extended with:

* Timer drivers
* Interrupt controller drivers
* DSP accelerator drivers
* FIFO drivers
* RAM controller drivers
* Audio processing control software
* Bare-metal application examples
* Startup/runtime support
* More complete exception handling

The software architecture is intentionally kept simple so that these components can be added without changing the CPU's fundamental execution model.
