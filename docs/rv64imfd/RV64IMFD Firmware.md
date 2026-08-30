# RV64IMFD Firmware

## 1. Overview

A bare-metal firmware environment is provided for the RV64IMFD processor.

The firmware is designed to execute directly from the SoC memory space without an operating system.

The basic software structure is:

```text
boot.S
   |
   v
reset_handler
   |
   v
main()
```

---

## 2. Toolchain

The intended compiler target is:

```text
riscv64-unknown-elf-gcc
```

with:

```text
-march=rv64imfd
-mabi=lp64d
```

The firmware is compiled as a freestanding environment.

---

## 3. Startup Code

The startup assembly provides:

- Reset vector
- Interrupt vector
- Stack initialization
- Entry into `main`
- Halt/WFI fallback

The reset vector begins at the beginning of the firmware image.

The interrupt vector follows the reset vector.

---

## 4. Linker Script

The linker script defines the main RAM region:

```text
ORIGIN = 0x00004000
LENGTH = 0x4000
```

This corresponds to the current 16 KiB unified RAM configuration.

The stack is placed at:

```text
0x00008000
```

which is the upper boundary of the defined RAM region.

---

## 5. Software Memory Map

The C firmware accesses MMIO peripherals through:

```text
soc_map.h
```

The header defines 32-bit and 64-bit volatile register types.

Core peripheral registers are currently represented as 32-bit registers on the 64-bit processor bus.

---

## 6. Timer Registers

The timer is accessed through:

```text
TIMER_CTRL
TIMER_COMPARE
TIMER_COUNTER
TIMER_STATUS
```

---

## 7. Interrupt Registers

The interrupt arbiter exposes:

```text
IRQ_PENDING
IRQ_ENABLE
IRQ_CLEAR
```

---

## 8. Firmware Entry

The startup sequence initializes the stack and calls:

```text
main()
```

The current firmware expects `main()` not to return.

A WFI-based halt loop is used as the fallback execution state.

---

## 9. Interrupt Handler

The timer interrupt handler is declared using the compiler's machine interrupt attribute.

The current handler clears the timer status condition.

The implementation is intended for the current processor interrupt model and should be considered part of the experimental firmware environment.

---

## 10. Bare-Metal Constraints

The firmware uses:

```text
-freestanding
-fno-builtin
-nostdlib
```

No standard C runtime or operating system is assumed.

This is important because the processor environment currently provides only the low-level hardware required by the firmware.

---

## 11. Memory Image Generation

After linking, the ELF image can be converted into a Verilog memory initialization file.

The current build flow generates:

```text
firmware.elf
firmware.mem
firmware.dump
```

The `.mem` file is intended for RTL simulation.

The disassembly file is useful for debugging instruction execution and comparing the expected program flow with simulation traces.

---

## 12. Simulation Usage

The firmware is primarily intended to support CPU and SoC testbench development.

A typical simulation flow is:

```text
Compile firmware
       |
       v
Generate firmware.mem
       |
       v
Load into simulation memory
       |
       v
Run RV64IMFD CPU
       |
       v
Observe execution
```

---

## 13. Current Firmware Status

The firmware environment is functional as a development and simulation aid.

It is not currently intended to represent a complete operating-system environment.

The firmware and hardware interface may change as the RV64IMFD SoC architecture evolves.