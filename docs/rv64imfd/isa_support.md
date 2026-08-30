# RV64IMFD ISA Support

## 1. Target ISA

The processor targets:

```text
RV64IMFD
```

The extensions are:

- `I` — Base Integer ISA
- `M` — Integer Multiply/Divide
- `F` — Single-Precision Floating Point
- `D` — Double-Precision Floating Point

This document describes the intended and currently implemented instruction groups.

It does not constitute a formal RISC-V compliance certificate.

---

## 2. RV64I

The integer base architecture includes the major RV64I instruction categories.

### Integer Arithmetic

```text
ADD
SUB
ADDI
```

### Logical Operations

```text
AND
OR
XOR
ANDI
ORI
XORI
```

### Comparisons

```text
SLT
SLTU
SLTI
SLTIU
```

### Shift Operations

```text
SLL
SRL
SRA
SLLI
SRLI
SRAI
```

### Word Operations

```text
ADDW
SUBW
SLLW
SRLW
SRAW
ADDIW
SLLIW
SRLIW
SRAIW
```

### Immediate and PC-Relative Operations

```text
LUI
AUIPC
```

### Control Transfer

```text
JAL
JALR
BEQ
BNE
BLT
BGE
BLTU
BGEU
```

### Loads

```text
LB
LH
LW
LD
LBU
LHU
LWU
```

### Stores

```text
SB
SH
SW
SD
```

---

## 3. RV64M

The M extension is implemented through:

```text
vrm_mdu_rv64m
```

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

The divider implements architectural handling for division-by-zero and signed overflow corner cases.

---

## 4. RV64F/D

Floating-point execution is provided through:

```text
vrm_fpu_rv64fd
```

The FPU subsystem supports the CPU-facing implementation of floating-point operations including:

```text
FADD
FSUB
FMUL
FDIV
FSQRT
```

along with conversion, move, comparison, classification, and additional mathematical functions implemented by the VRM21 FPU subsystem.

The exact implementation of each operation is maintained in the dedicated FPU repository.

---

## 5. Floating-Point Register File

The CPU provides:

```text
f0 ... f31
```

with each register represented internally as 64 bits.

Single-precision values are maintained using the appropriate RV64 floating-point representation, including NaN-boxing behavior for 32-bit floating-point loads.

---

## 6. Integer/Floating-Point Conversion

The CPU provides routing between:

```text
GPR → FPU
FPU → GPR
```

This is required for operations such as integer/FP conversion and register moves.

---

## 7. System Instructions

The current implementation contains dedicated handling for:

```text
MRET
WFI
```

These instructions are primarily used by the current machine-mode interrupt and firmware environment.

---

## 8. Unsupported or Unverified Areas

The presence of an instruction decoder path does not automatically imply complete architectural compliance.

The following require continued verification:

- Complete floating-point exception behavior
- Rounding-mode coverage
- NaN propagation
- Signaling NaN behavior
- All architectural corner cases
- Complete privileged ISA behavior
- Formal compliance against the complete RISC-V specification

---

## 9. ISA Status

| Extension | Implementation | Verification |
|---|---|---|
| RV64I | Implemented | Ongoing |
| RV64M | Implemented | Ongoing |
| RV64F | Integrated | Ongoing |
| RV64D | Integrated | Ongoing |
| Privileged functionality | Partial/custom | Ongoing |

Full compliance is not currently claimed.
