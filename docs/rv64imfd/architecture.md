# RV64IMFD Architecture

## 1. Overview

The `vrm_cpu_rv64_core` is a 64-bit RISC-V processor core implementing the RV64IMFD architecture.

The core combines a pipelined integer datapath with dedicated Multiply/Divide and Floating-Point execution units.

The current architecture is organized around the following major blocks:

```text
+---------------------------------------------------------------+
|                     vrm_cpu_rv64_core                        |
|                                                               |
|  +---------+    +---------+    +--------------------------+  |
|  |   IF    | -> |   ID    | -> |           EX             |  |
|  +---------+    +---------+    +--------------------------+  |
|                                      |       |       |        |
|                                      |       |       |        |
|                                     ALU     MDU     FPU       |
|                                      |       |       |        |
|                                      +-------+-------+        |
|                                              |                |
|                                           EX/MEM              |
|                                              |                |
|                                           MEM                  |
|                                              |                |
|                                           MEM/WB               |
|                                              |                |
|                                             WB                  |
|                                                               |
+---------------------------------------------------------------+
```

The core is intended to operate as the processor element of a larger SoC architecture.

---

## 2. Processor Datapath

The processor contains:

- 64-bit program counter
- 32-entry, 64-bit integer register file
- 32-entry, 64-bit floating-point register file
- RV64I ALU
- RV64M Multiply/Divide Unit
- RV64F/D Floating-Point Unit
- Branch and jump logic
- Load/store address generation
- Data alignment and byte-strobe generation
- Pipeline forwarding
- Pipeline stall and flush control

The integer and floating-point register files are maintained independently.

```text
Integer Register File
x0 ... x31
64-bit each

Floating-Point Register File
f0 ... f31
64-bit each
```

Register `x0` is hardwired to zero through the read path and is not written during writeback.

---

## 3. Pipeline Organization

The current pipeline is logically divided into:

```text
IF → ID → EX → MEM → WB
```

Pipeline registers are used between the major execution stages.

### IF/ID

Stores:

- Program counter
- Instruction word

### ID/EX

Stores:

- Register operands
- Floating-point operands
- Immediate values
- Register indices
- Instruction classification
- ALU control
- MDU control
- FPU control
- Memory control
- Branch/jump control

### EX/MEM

Stores:

- ALU result
- FPU result
- Destination register
- Memory write data
- Memory write strobes
- Register write controls
- Memory controls

### MEM/WB

Stores:

- ALU result
- FPU result
- Memory read data
- Destination register
- Register write controls
- Load information

---

## 4. Execution Units

### 4.1 Integer ALU

The integer ALU handles RV64I arithmetic, logical, shift, and comparison operations.

It is instantiated as:

```text
vrm_alu_rv64i
```

The ALU is used for both normal arithmetic and address-generation operations.

---

### 4.2 Multiply/Divide Unit

The MDU is instantiated as:

```text
vrm_mdu_rv64m
```

The unit implements the RV64M arithmetic operations.

Multiplication is implemented as a combinational multiplication path intended to allow FPGA DSP inference.

Division uses an iterative radix-2 algorithm.

The CPU provides dedicated stall control for the multi-cycle divider.

---

### 4.3 Floating-Point Unit

The FPU is instantiated as:

```text
vrm_fpu_rv64fd
```

The wrapper provides the CPU-facing interface to the dedicated VRM21 FPU subsystem.

The internal FPU is divided into functional execution lanes.

The CPU supports routing between the integer and floating-point register files for conversion and move instructions.

---

## 5. Register Routing

The processor contains two independent register domains.

```text
                 +----------------+
                 | Integer RF     |
                 | x0 - x31       |
                 +-------+--------+
                         |
                         | Integer operands
                         v
                       +---+
                       | ALU|
                       +---+
                         ^
                         |
                         |
                 +-------+--------+
                 | FPU conversion |
                 +-------+--------+
                         ^
                         |
                         |
                 +-------+--------+
                 | Floating RF    |
                 | f0 - f31       |
                 +----------------+
```

Cross-register operations include:

- Integer-to-floating conversion
- Floating-to-integer conversion
- Floating/integer register moves
- Floating comparison results
- Floating classification results

---

## 6. Forwarding Architecture

The processor implements separate forwarding paths for integer and floating-point operands.

Integer forwarding can select:

```text
ID/EX register value
EX/MEM result
MEM/WB result
```

Floating-point forwarding similarly allows results from later pipeline stages to be used by a dependent floating-point instruction.

This reduces unnecessary stalls for common producer-consumer sequences.

---

## 7. Control Flow

Branch and jump instructions are resolved in the execute stage.

The processor generates:

```text
branch_taken_ex
target_pc_ex
flush_ex
```

When a control-flow instruction is taken, instructions belonging to the wrong execution path are invalidated.

The current implementation also handles:

```text
JAL
JALR
conditional branches
MRET
```

---

## 8. Interrupt Entry

Interrupt processing is integrated into the program-counter control logic.

When an interrupt is accepted:

1. The current PC is stored in `mepc`.
2. The processor enters interrupt state.
3. The PC is redirected to the interrupt vector.
4. Pipeline state is flushed as required.
5. Further interrupt entry is blocked while already inside the handler.

The current implementation uses a simplified machine-mode interrupt mechanism intended for the integrated SoC environment.

---

## 9. Wait For Interrupt

The core supports `WFI`.

When the processor reaches a WFI state without an active interrupt, the core exposes:

```text
cpu_halt = 1
```

The processor remains halted until an interrupt becomes available.

---

## 10. SoC Integration

The processor can be integrated through:

```text
vrm_cpu_rv64_wrapper
```

The wrapper provides:

- Local timer
- Interrupt arbiter
- External memory interface
- External interrupt synchronization
- Memory-mapped peripheral routing

This separation allows the CPU core to remain relatively independent from the surrounding SoC infrastructure.

---

## 11. Design Philosophy

The architecture is designed around modular hardware blocks.

The processor core does not directly implement every peripheral function. Instead, dedicated modules provide system-level services.

This allows future VRM21-Studios designs to connect additional accelerators or peripherals without fundamentally changing the CPU datapath.

---

## 12. Current Architectural Status

The architecture is implemented in RTL and is undergoing verification.

The documentation should therefore be interpreted as a description of the current implementation rather than a declaration of complete RISC-V architectural compliance.
