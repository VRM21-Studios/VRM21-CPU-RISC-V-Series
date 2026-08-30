# VRM RV64IMFD CPU Core

The `vrm_cpu_rv64_core` is a 64-bit RISC-V processor core implementing the base **RV64I** instruction set together with the **M**, **F**, and **D** extensions.

The core integrates:

* 64-bit integer datapath
* Integer ALU
* Multiply/Divide Unit (MDU)
* Floating-Point Unit (FPU)
* Integer and floating-point register files
* Load/store memory interface
* Five-stage-style pipelined datapath
* Basic hazard detection and data forwarding
* Branch and jump handling
* Interrupt entry and `MRET`
* `WFI` handling
* Byte-enable memory write interface
* 32-bit and 64-bit load/store handling
* Floating-point load/store operations
* Basic GPR/FPR cross-domain routing for floating-point conversion and move operations

The design is intended as a synthesizable and extensible RV64 processor core for FPGA-based hardware systems.

---

## Current Verification Status

| Area                            | Status                                    |
| ------------------------------- | ----------------------------------------- |
| RV64I ALU operations            | **Passed — simulation stress test**       |
| Integer multiply/divide         | **Passed — simulation stress test**       |
| Load/store path                 | **Passed — simulation stress test**       |
| Conditional branch              | **Passed — simulation stress test**       |
| FPU integration                 | **Passed — basic simulation stress test** |
| `WFI` / CPU halt                | **Passed — simulation stress test**       |
| Full RV64I compliance           | **Not yet exhaustively verified**         |
| Full M extension compliance     | **Not yet exhaustively verified**         |
| Full F/D extension compliance   | **Not yet exhaustively verified**         |
| FPGA CPU integration validation | **Not yet verified**                      |

The current simulation demonstrates successful execution of representative integer, memory, branch, and floating-point instructions. It is a functional stress test rather than a complete architectural compliance suite.

---

## Tested FPU Path

The current CPU stress test validates the basic CPU-to-FPU integration path using floating-point values loaded directly from memory.

Tested operations include:

```text
FLD
FADD.D
FMUL.D
```

The resulting register values were:

```text
f2 = 4062C00000000000   // 150.0
f3 = 40B3880000000000   // 5000.0
```

These values match the expected IEEE-754 double-precision representations.

Using `FLD` directly also isolates the basic FPU execution and FPR writeback path from the integer-to-floating-point conversion path.

---

## Architecture Overview

The core follows a pipelined organization consisting of:

```text
Instruction Fetch
       |
       v
Instruction Decode / Register Read
       |
       v
Execute
  |      |
 ALU    MDU/FPU
       |
       v
Memory Access
       |
       v
Writeback
```

Hazard handling and forwarding logic are included to allow dependent integer and floating-point operations to execute correctly under the currently supported pipeline behavior.

---

## Memory Interface

The core exposes a simple synchronous-style data memory interface:

```text
mem_addr
mem_wdata
mem_we
mem_wstrb
mem_rdata
mem_busy
```

`mem_wstrb` provides byte-level write enables for store operations.

Supported integer load/store formats include:

```text
LB
LH
LW
LD
LBU
LHU
LWU

SB
SH
SW
SD
```

Floating-point memory operations include the corresponding floating-point load/store paths currently implemented by the core.

---

## Interrupt and Privileged Control

The implementation includes basic support for:

* External interrupt entry
* `mepc` storage
* Interrupt masking while already inside the ISR
* `MRET`
* `WFI`

The current implementation is intentionally lightweight and should not be interpreted as a complete RISC-V privileged architecture implementation.

---

## Verification Scope

The current stress test covers representative functionality rather than every instruction encoding.

Therefore, passing the current test does **not** establish:

* Full RV64I compliance
* Full RV64M compliance
* Full IEEE-754 compliance
* Full RV64F compliance
* Full RV64D compliance
* Complete privileged architecture compliance
* Complete exception handling compliance
* Formal verification
* FPGA-level CPU integration validation

Additional directed tests and architectural compliance testing are required before making those claims.

---

## Related Documentation

* `verification.md` — simulation verification scope and results
* `limitations.md` — known limitations and current verification boundaries
* `architecture.md` — high-level architecture and pipeline description
* `isa_support.md` — implemented instruction categories
