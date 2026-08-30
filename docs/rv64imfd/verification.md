# RV64IMFD Verification

## Overview

The `vrm_cpu_rv64_core` has undergone a core-level simulation stress test covering representative functionality from the RV64I, M, and basic F/D execution paths.

The testbench executes a small firmware image directly from a behavioral instruction-memory model and uses a behavioral byte-addressable data-memory model.

The test is intended to verify functional integration of the major CPU datapaths rather than provide exhaustive ISA compliance coverage.

---

## Testbench

The main stress testbench is:

```text
tb_vrm_cpu_rv64_core
```

The testbench provides:

* Instruction memory model
* Data memory model
* Clock and reset generation
* Software-like instruction generation through Verilog helper tasks
* Integer arithmetic tests
* Multiply/divide tests
* Load/store tests
* Branch-loop test
* Floating-point load and arithmetic tests
* `WFI` halt detection
* Final architectural register inspection

The firmware is generated using helper tasks such as:

```text
ADDI
ADD
SUB
SLLI
LD
SD
BNE
MUL
DIV
FLD
FADD_D
FMUL_D
WFI
```

---

## Simulation Result

The stress test completed successfully and reached the expected `WFI` halt state.

Representative console output:

```text
[CPU] HALT REACHED. Test Complete.
```

The following results were observed.

### Integer ALU

| Test | Register | Actual | Expected | Result |
| ---- | -------: | -----: | -------: | ------ |
| ADD  |       x3 |    150 |      150 | PASS   |
| SUB  |       x4 |     50 |       50 | PASS   |
| SLLI |       x5 |    400 |      400 | PASS   |

### Integer M Extension

| Test | Register | Actual | Expected | Result |
| ---- | -------: | -----: | -------: | ------ |
| MUL  |       x6 |   5000 |     5000 | PASS   |
| DIV  |       x7 |      2 |        2 | PASS   |

### Memory Path

| Test | Register | Actual | Expected | Result |
| ---- | -------: | -----: | -------: | ------ |
| LD   |       x8 |   5000 |     5000 | PASS   |
| LD   |       x9 |      2 |        2 | PASS   |

The preceding `SD` operations were used to populate the behavioral data memory.

### Branch

The test executes a decrementing loop using `BNE`.

| Test     | Register | Actual | Expected | Result |
| -------- | -------: | -----: | -------: | ------ |
| BNE loop |      x10 |      0 |        0 | PASS   |

This verifies the tested branch condition, immediate generation, target calculation, and pipeline flush behavior.

---

## Floating-Point Integration

The FPU path was tested by loading IEEE-754 double-precision operands directly from memory.

The firmware performs:

```text
FLD f0, ...
FLD f1, ...

FADD.D f2, f0, f1
FMUL.D f3, f0, f1
```

Expected values:

```text
f0 = 100.0
f1 = 50.0

f2 = 150.0
f3 = 5000.0
```

Observed register contents:

```text
f2 = 4062C00000000000
f3 = 40B3880000000000
```

These correspond to:

```text
4062C00000000000 = 150.0
40B3880000000000 = 5000.0
```

Result:

```text
FADD.D : PASS
FMUL.D : PASS
FPR writeback : PASS
```

This test specifically validates the basic CPU/FPU integration path:

```text
FLD
  |
  v
FPR
  |
  v
FPU
  |
  v
FPR writeback
```

---

## WFI / Halt

The firmware terminates with:

```text
WFI
```

The testbench waits for:

```text
cpu_halt == 1'b1
```

The CPU reached the expected halt state within the simulation timeout.

Result:

```text
WFI / CPU halt : PASS
```

---

## Verification Summary

| Functional Area  | Result |
| ---------------- | ------ |
| Integer ALU      | PASS   |
| Integer multiply | PASS   |
| Integer divide   | PASS   |
| Load/store       | PASS   |
| Branch loop      | PASS   |
| FPU load         | PASS   |
| FADD.D           | PASS   |
| FMUL.D           | PASS   |
| FPR writeback    | PASS   |
| WFI / halt       | PASS   |

---

## Verification Boundary

This test should be considered a **functional integration stress test**.

It does not constitute exhaustive ISA compliance testing.

The following areas require additional verification:

* Complete RV64I instruction coverage
* Complete RV64M instruction coverage
* Complete RV64F instruction coverage
* Complete RV64D instruction coverage
* Floating-point corner cases
* NaN and infinity behavior
* Rounding modes
* Exceptions and traps
* Privileged instructions
* CSR behavior
* Interrupt corner cases
* Misaligned memory access behavior
* Formal verification
* FPGA-level CPU integration

Accordingly, the current status is:

> **Core-level simulation stress test passed; exhaustive architectural verification remains ongoing.**
