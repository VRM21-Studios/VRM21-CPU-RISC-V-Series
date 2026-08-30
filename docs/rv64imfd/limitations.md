# RV64IMFD Limitations

This document describes the current limitations and verification boundaries of the `vrm_cpu_rv64_core`.

The core has successfully passed a representative simulation stress test, but the current implementation should not yet be considered a fully compliant RV64IMFD processor.

---

## 1. ISA Verification Scope

The current testbench exercises a selected subset of the implemented instruction paths.

Passing the current stress test does not prove complete compliance with:

```text
RV64I
RV64M
RV64F
RV64D
```

A dedicated instruction-by-instruction compliance test suite is still required.

---

## 2. Floating-Point Verification

The integrated FPU path has been successfully exercised in simulation using:

```text
FLD
FADD.D
FMUL.D
```

The test produced the expected IEEE-754 results for the selected operands.

However, this does not constitute complete verification of the F and D extensions.

Additional verification is required for:

* All arithmetic operations
* Comparisons
* Conversions
* Move instructions
* Classification
* Square root
* Division
* NaN handling
* Infinity handling
* Signed zero
* Subnormal values
* Rounding modes
* Floating-point exception behavior
* Complete instruction encoding coverage

---

## 3. FPGA Validation

The standalone FPU implementation has been validated independently on FPGA.

However, the **RV64IMFD CPU core with the integrated FPU has not yet undergone full FPGA validation**.

Therefore, the following should currently be considered unverified at FPGA level:

```text
CPU pipeline
      +
MDU integration
      +
FPU integration
      +
Memory interface
      +
Interrupt/control logic
```

FPGA validation is planned as a separate verification stage.

---

## 4. Privileged Architecture

The core contains basic support for:

```text
WFI
MRET
Interrupt entry
mepc
```

The implementation is not intended to claim complete RISC-V privileged architecture compliance.

In particular, a complete CSR subsystem and comprehensive trap/exception architecture are outside the current verification scope.

---

## 5. Memory System

The CPU exposes a simple data-memory interface rather than a complete cache/MMU subsystem.

The current design does not provide:

* Instruction cache
* Data cache
* MMU
* TLB
* Virtual memory
* Full atomic memory subsystem
* Bus protocol compliance beyond the exposed custom interface

The behavioral simulation memory is also considerably simpler than a real external memory subsystem.

---

## 6. Memory Alignment

The load/store datapath contains byte-enable generation and load extraction logic for the currently supported access sizes.

However, exhaustive verification of:

* Misaligned loads
* Misaligned stores
* Cross-boundary accesses
* Memory exceptions

has not yet been completed.

---

## 7. Hazard and Pipeline Verification

The design contains load-use hazard detection and forwarding paths for integer and floating-point registers.

The current stress test demonstrates successful execution of selected dependent instruction sequences.

Nevertheless, exhaustive pipeline verification has not yet been performed for every possible dependency combination.

Potential future verification should include:

* ALU-to-ALU dependencies
* Load-to-use dependencies
* MDU-to-ALU dependencies
* FPU-to-FPU dependencies
* FPU-to-GPR dependencies
* GPR-to-FPU dependencies
* Memory stalls combined with dependencies
* Branches following long-latency operations
* Interrupts during stalled operations

---

## 8. Interrupt Handling

Interrupt handling is intentionally lightweight.

The current implementation uses a simple `irq` input and internal ISR state.

It should not yet be considered a complete machine-mode interrupt implementation.

Additional work is required for comprehensive interrupt and exception behavior.

---

## 9. Formal Verification

No formal verification result is currently claimed.

The current evidence is based on directed simulation and stress-test execution.

Formal property checking may be added in a future verification stage.

---

## 10. Compliance Status

The current status can be summarized as:

| Area                               | Status                      |
| ---------------------------------- | --------------------------- |
| Core-level simulation              | **Passed for tested paths** |
| ALU                                | **Passed in stress test**   |
| MDU                                | **Passed in stress test**   |
| Memory path                        | **Passed in stress test**   |
| Branch path                        | **Passed in stress test**   |
| Basic FPU integration              | **Passed in stress test**   |
| Full ISA compliance                | **Not yet established**     |
| Privileged architecture compliance | **Not yet established**     |
| Formal verification                | **Not yet performed**       |
| CPU + FPU FPGA validation          | **Not yet performed**       |

The appropriate overall description is therefore:

> **Functionally demonstrated through core-level simulation, with exhaustive ISA verification and FPGA CPU integration validation still pending.**
