# RV64IMFD Verification

## 1. Overview

Verification of the RV64IMFD system is performed incrementally.

The verification strategy separates:

```text
Unit Verification
       ↓
Subsystem Verification
       ↓
CPU Integration
       ↓
SoC Integration
       ↓
Firmware Execution
       ↓
FPGA Validation
```

Passing one level does not automatically imply that the higher-level system is fully verified.

---

## 2. Unit-Level Verification

Individual hardware blocks should be tested independently where practical.

Primary units include:

```text
vrm_alu_rv64i
vrm_mdu_rv64m
vrm_fpu_rv64fd
vrm_cpu_timer_64
vrm_cpu_irq_arbiter_64
```

---

## 3. ALU Verification

The ALU verification should cover:

- Arithmetic operations
- Logical operations
- Shift operations
- Signed comparisons
- Unsigned comparisons
- Immediate operations
- Word operations

Boundary values should be included in the test vectors.

---

## 4. MDU Verification

MDU testing should cover:

### Multiplication

```text
MUL
MULH
MULHSU
MULHU
MULW
```

### Division

```text
DIV
DIVU
DIVW
DIVUW
```

### Remainder

```text
REM
REMU
REMW
REMUW
```

Special cases include:

```text
division by zero
signed overflow
zero operands
negative operands
maximum/minimum values
```

---

## 5. FPU Verification

FPU verification is performed in conjunction with the dedicated:

```text
VRM21-FPU-Series
```

CPU-level verification must additionally test:

- Operand routing
- Result routing
- Integer/FP register transfers
- FPU forwarding
- FPU stalls
- Floating-point loads/stores
- NaN-boxing
- Multi-cycle operation behavior

---

## 6. Pipeline Verification

Pipeline tests should deliberately create dependencies.

Examples include:

```text
ALU → ALU dependency
LOAD → ALU dependency
MDU → ALU dependency
FPU → FPU dependency
FPU → GPR dependency
GPR → FPU dependency
```

Control hazards should include:

```text
taken branch
not-taken branch
JAL
JALR
MRET
```

---

## 7. Memory Verification

Memory testing should cover:

```text
LB
LBU
LH
LHU
LW
LWU
LD

SB
SH
SW
SD
```

Tests should include different byte offsets and memory wait states.

---

## 8. Interrupt Verification

Interrupt tests should cover:

- Timer interrupt generation
- External interrupt synchronization
- Pending interrupt generation
- Interrupt enable masking
- Pending interrupt clearing
- CPU interrupt entry
- `mepc`
- Interrupt handler execution
- `MRET`
- WFI wake-up

---

## 9. Firmware-Level Verification

The GCC firmware provides an end-to-end execution test.

The test sequence should verify:

```text
Reset
 ↓
Boot
 ↓
Stack initialization
 ↓
C runtime entry
 ↓
MMIO access
 ↓
Interrupt operation
 ↓
WFI
```

---

## 10. Waveform Inspection

For debugging, important signals include:

```text
pc
if_id_pc
if_id_instr

id_ex_opcode
id_ex_rd
id_ex_rs1
id_ex_rs2

ex_mem_alu_res
ex_mem_rd

mem_wb_rd
mem_wb_reg_we
mem_wb_freg_we

stall_load_use
stall_mdu
stall_fpu
mem_busy

mdu_valid_out
fpu_valid_out

irq_trigger
in_isr
mepc
```

These signals provide visibility into pipeline progression and stall/flush behavior.

---

## 11. Reference Model

Where practical, arithmetic results should be compared against a software reference model.

For example:

```text
RTL MDU result
        vs
software integer arithmetic
```

and:

```text
RTL FPU result
        vs
reference floating-point implementation
```

The reference model should also account for architectural corner cases rather than relying only on ordinary numerical examples.

---

## 12. Simulation Status

The simulation environment is under active development.

Individual blocks may reach different verification maturity levels.

Therefore, verification status should be tracked per subsystem rather than represented by a single overall "verified" label.

---

## 13. FPGA Validation

FPGA validation is a separate stage.

A successful RTL simulation does not constitute FPGA validation.

FPGA testing should verify:

- Synthesis
- Timing
- Resource utilization
- DSP inference
- RAM inference
- Multi-cycle operation
- Reset behavior
- Interrupt behavior
- Firmware execution
- External memory interface behavior

---

## 14. Compliance

No complete RISC-V architectural compliance claim is made at this stage.

Formal compliance testing should be performed after the RTL architecture and verification environment have stabilized.

---

## 15. Verification Status

| Area | Status |
|---|---|
| ALU | Implemented / verification ongoing |
| MDU | Implemented / verification ongoing |
| FPU | Integrated / verification ongoing |
| Pipeline | Verification ongoing |
| Memory | Verification ongoing |
| Timer | Implemented / verification ongoing |
| Interrupts | Verification ongoing |
| Firmware | Initial environment |
| Full ISA compliance | Not yet claimed |
| FPGA validation | Pending / ongoing |