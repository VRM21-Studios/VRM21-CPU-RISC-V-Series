# Interrupt System

## 1. Overview

The current RV64IMFD SoC integration provides a hardware interrupt path consisting of:

```text
External Interrupt Sources
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

A hardware timer is also connected as an internal interrupt source.

---

## 2. External Interrupt Synchronization

External interrupt inputs are asynchronous to the CPU clock domain.

The wrapper therefore uses two stages of flip-flops:

```text
ext_irq_sync1
ext_irq_sync2
```

This reduces the risk of metastability propagating into the CPU logic.

---

## 3. Interrupt Sources

The current interrupt source vector is 32 bits.

Source assignment:

```text
bit 0      = hardware timer
bits 31:1  = synchronized external interrupt inputs
```

---

## 4. Interrupt Arbiter

The interrupt arbiter is:

```text
vrm_cpu_irq_arbiter_64
```

It maintains:

```text
pending
enable
irq_src_d1
```

The arbiter detects rising edges on interrupt sources.

---

## 5. Pending Register

An interrupt becomes pending when a rising edge is detected.

Pending interrupts remain latched until cleared.

The pending register can be accessed through MMIO.

---

## 6. Enable Register

The enable register determines which pending interrupt sources are allowed to generate the CPU interrupt signal.

The CPU interrupt output is effectively:

```text
|(pending & enable)
```

---

## 7. Interrupt Clearing

Pending interrupts can be cleared through the MMIO interface.

The current implementation uses write-to-clear behavior for the pending register.

---

## 8. Hardware Timer

The hardware timer is implemented by:

```text
vrm_cpu_timer_64
```

The internal timer registers are:

```text
CTRL
COMPARE
COUNTER
STATUS
```

The timer generates an interrupt when enabled and the counter reaches the configured comparison value.

---

## 9. CPU Interrupt Entry

The CPU receives:

```text
irq
```

from the interrupt arbiter.

An interrupt is accepted when:

```text
irq == 1
```

and the CPU is not already handling an interrupt.

The current implementation tracks interrupt state through:

```text
in_isr
mepc
```

---

## 10. Interrupt Vector

The current CPU redirects accepted interrupts to:

```text
0x0000_0000_0000_4004
```

The corresponding firmware layout places the interrupt vector immediately after the reset vector.

---

## 11. Machine Return

The CPU recognizes:

```text
MRET
```

and restores execution from:

```text
mepc
```

---

## 12. Firmware Interaction

The intended firmware structure is:

```text
Reset Vector
     |
     v
Reset Handler
     |
     v
Main Program

Interrupt Vector
     |
     v
Interrupt Handler
     |
     v
MRET
```

---

## 13. WFI Interaction

The CPU can enter a halted state after executing:

```text
WFI
```

An interrupt can release the processor from this state.

The wrapper exposes the current state through:

```text
cpu_halt
```

---

## 14. Current Limitations

The current interrupt architecture is intentionally lightweight.

It should not be interpreted as a complete implementation of the RISC-V privileged architecture.

Areas requiring further verification include:

- Nested interrupts
- Interrupt priority
- Precise interrupt timing
- Full machine-status CSR behavior
- Interrupt masking semantics
- Precise exception interaction

---

## 15. Current Status

The timer, interrupt arbiter, synchronization logic, and CPU interrupt routing are implemented in RTL.

System-level interrupt verification remains ongoing.
