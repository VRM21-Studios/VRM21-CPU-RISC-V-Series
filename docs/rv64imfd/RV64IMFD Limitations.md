# RV64IMFD Limitations

## 1. Overview

The RV64IMFD processor is an active hardware-development project.

The RTL should therefore be considered an evolving implementation rather than a finalized commercial processor core.

This document records important limitations and areas that require additional verification.

---

## 2. ISA Compliance

The processor targets RV64IMFD but complete RISC-V architectural compliance has not yet been formally established.

Passing selected instruction tests is not sufficient to claim complete compliance.

---

## 3. Privileged Architecture

The current implementation contains selected machine-level functionality such as:

```text
MRET
WFI
interrupt entry
```

However, it does not currently represent a complete implementation of the RISC-V privileged architecture.

In particular, the current implementation uses a simplified interrupt mechanism rather than a complete CSR-based machine-mode environment.

---

## 4. Floating-Point Compliance

The FPU subsystem is integrated but complete IEEE-754 and RISC-V floating-point compliance is still subject to verification.

Areas requiring particular attention include:

- Rounding modes
- Exceptional values
- NaN behavior
- Signaling NaNs
- Infinities
- Subnormal values
- Conversion corner cases
- Floating-point flags

---

## 5. Pipeline Verification

The pipeline combines several independent stall sources:

```text
Load-Use
MDU
FPU
Memory
```

and several flush sources:

```text
Branch
Jump
MRET
Interrupt
```

Interactions between these conditions require extensive verification.

---

## 6. Memory System

The current memory interface is intentionally simple.

It provides:

```text
64-bit data bus
8-bit write strobe
memory busy signal
```

It does not itself implement a complete cache hierarchy or memory-coherency system.

---

## 7. External Memory Protocol

The external memory interface can be connected to a larger memory subsystem, but the CPU core itself does not define a complete external bus protocol such as AXI.

Protocol conversion is expected to be handled by surrounding SoC logic.

---

## 8. Interrupt Architecture

The current interrupt system is lightweight and tailored to the current SoC architecture.

It does not currently claim support for all features of a complete RISC-V interrupt controller architecture.

---

## 9. Debug Features

The current core exposes limited debug visibility.

The primary architectural debug output is:

```text
debug_reg_x1
```

This should not be interpreted as a complete hardware debug interface.

---

## 10. Performance

The current implementation prioritizes modularity and functional development over maximum performance.

In particular:

- Division is iterative.
- FPU operations may require multiple cycles.
- Pipeline stalls are used around multi-cycle execution units.
- No cache hierarchy is currently integrated into the core.
- Branch prediction is not implemented.

These characteristics affect throughput and latency.

---

## 11. FPGA Validation

RTL implementation and simulation results should not be interpreted as FPGA validation.

Hardware validation must separately confirm:

- Synthesis
- Timing closure
- Resource mapping
- DSP utilization
- Memory inference
- Reset behavior
- Multi-cycle execution
- Firmware execution

---

## 12. Firmware Environment

The current GCC firmware environment is a bare-metal development environment.

It does not provide:

- Operating system support
- Standard runtime environment
- Dynamic memory management
- Full libc environment
- Process isolation

The firmware is primarily intended for simulation and hardware bring-up.

---

## 13. Future Expansion

Several address ranges and architectural interfaces are intentionally reserved for future VRM21-Studios accelerators and peripherals.

Reserved address space should not be interpreted as evidence that the corresponding hardware is currently implemented or validated.

---

## 14. Development Status

The RV64IMFD core should currently be considered:

```text
Experimental / Development
```

rather than:

```text
Production-ready
```

The architecture, RTL, firmware interface, and verification environment may change as development progresses.

---

## 15. Summary

The major current limitations are:

- Full ISA compliance not yet formally established
- Privileged architecture is partial
- Floating-point compliance requires further verification
- Pipeline corner cases require continued testing
- External memory protocol is intentionally simple
- No cache hierarchy
- No branch prediction
- Limited debug infrastructure
- FPGA validation remains separate from RTL verification

These limitations are expected to decrease as the project progresses through verification and hardware validation.