# VRM RV32I CPU — Instruction Set

## 1. Overview

The CPU implements the RV32I base integer instruction set required by the current RTL design.

Instructions are 32 bits wide and follow the standard RISC-V encoding formats.

The supported instruction groups are:

* U-type
* J-type
* B-type
* I-type
* S-type
* R-type
* Selected SYSTEM instructions

---

## 2. Instruction Support Summary

| Type        | Instructions                                                           |
| ----------- | ---------------------------------------------------------------------- |
| U-Type      | `LUI`, `AUIPC`                                                         |
| J-Type      | `JAL`                                                                  |
| I-Type ALU  | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| I-Type Load | `LB`, `LH`, `LW`, `LBU`, `LHU`                                         |
| I-Type Jump | `JALR`                                                                 |
| R-Type      | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`   |
| S-Type      | `SB`, `SH`, `SW`                                                       |
| B-Type      | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`                             |
| SYSTEM      | `WFI`, `MRET`                                                          |

---

## 3. U-Type Instructions

### LUI

```asm
lui rd, imm
```

Loads the upper 20 bits of the immediate into the destination register.

```text
rd = imm[31:12] << 12
```

Example:

```asm
lui x20, 0x12345
```

produces:

```text
x20 = 0x12345000
```

---

### AUIPC

```asm
auipc rd, imm
```

Adds the upper immediate to the current program counter.

```text
rd = PC + (imm << 12)
```

The instruction is executed through the same ALU datapath used by the CPU's other arithmetic operations.

---

## 4. J-Type Instructions

### JAL

```asm
jal rd, offset
```

The instruction:

1. Stores the return address in `rd`
2. Redirects execution to the calculated target

```text
rd = PC + 4
PC = PC + offset
```

When `rd = x0`, the instruction behaves as an unconditional jump.

---

## 5. I-Type Arithmetic Instructions

### ADDI

```asm
addi rd, rs1, imm
```

```text
rd = rs1 + sign_extended(imm)
```

---

### SLTI

```asm
slti rd, rs1, imm
```

Performs signed comparison:

```text
rd = (signed(rs1) < signed(imm))
```

---

### SLTIU

```asm
sltiu rd, rs1, imm
```

Performs unsigned comparison:

```text
rd = (rs1 < unsigned(imm))
```

---

### XORI

```asm
xori rd, rs1, imm
```

```text
rd = rs1 ^ imm
```

---

### ORI

```asm
ori rd, rs1, imm
```

```text
rd = rs1 | imm
```

---

### ANDI

```asm
andi rd, rs1, imm
```

```text
rd = rs1 & imm
```

---

## 6. Shift Immediate Instructions

### SLLI

```asm
slli rd, rs1, shamt
```

Performs logical left shift.

---

### SRLI

```asm
srli rd, rs1, shamt
```

Performs logical right shift.

Zero bits are shifted into the upper portion of the result.

---

### SRAI

```asm
srai rd, rs1, shamt
```

Performs arithmetic right shift.

The sign bit is replicated during the shift.

---

## 7. Register-Register Arithmetic

### ADD

```asm
add rd, rs1, rs2
```

```text
rd = rs1 + rs2
```

### SUB

```asm
sub rd, rs1, rs2
```

```text
rd = rs1 - rs2
```

### SLL

```asm
sll rd, rs1, rs2
```

Logical left shift.

### SLT

```asm
slt rd, rs1, rs2
```

Signed comparison.

### SLTU

```asm
sltu rd, rs1, rs2
```

Unsigned comparison.

### XOR

```asm
xor rd, rs1, rs2
```

Bitwise XOR.

### SRL

```asm
srl rd, rs1, rs2
```

Logical right shift.

### SRA

```asm
sra rd, rs1, rs2
```

Arithmetic right shift.

### OR

```asm
or rd, rs1, rs2
```

Bitwise OR.

### AND

```asm
and rd, rs1, rs2
```

Bitwise AND.

---

## 8. Load Instructions

The CPU provides byte, halfword, and word loads.

### LB

```asm
lb rd, offset(rs1)
```

Loads one byte and sign-extends it to 32 bits.

### LH

```asm
lh rd, offset(rs1)
```

Loads one halfword and sign-extends it to 32 bits.

### LW

```asm
lw rd, offset(rs1)
```

Loads a complete 32-bit word.

### LBU

```asm
lbu rd, offset(rs1)
```

Loads one byte and zero-extends it.

### LHU

```asm
lhu rd, offset(rs1)
```

Loads one halfword and zero-extends it.

---

## 9. Store Instructions

### SB

```asm
sb rs2, offset(rs1)
```

Stores the lowest 8 bits of `rs2`.

The CPU generates the appropriate byte-enable based on:

```text
address[1:0]
```

---

### SH

```asm
sh rs2, offset(rs1)
```

Stores the lowest 16 bits of `rs2`.

The CPU generates two active byte-enable lanes.

---

### SW

```asm
sw rs2, offset(rs1)
```

Stores the complete 32-bit register value.

All four byte-enable lanes are asserted.

---

## 10. Branch Instructions

Branches are evaluated in the EX stage.

### BEQ

```asm
beq rs1, rs2, offset
```

Branch when:

```text
rs1 == rs2
```

### BNE

```asm
bne rs1, rs2, offset
```

Branch when:

```text
rs1 != rs2
```

### BLT

```asm
blt rs1, rs2, offset
```

Signed less-than comparison.

### BGE

```asm
bge rs1, rs2, offset
```

Signed greater-than-or-equal comparison.

### BLTU

```asm
bltu rs1, rs2, offset
```

Unsigned less-than comparison.

### BGEU

```asm
bgeu rs1, rs2, offset
```

Unsigned greater-than-or-equal comparison.

---

## 11. JALR

```asm
jalr rd, offset(rs1)
```

The target address is:

```text
target = (rs1 + sign_extended(offset)) & 0xFFFFFFFE
```

The return address is written to `rd`:

```text
rd = PC + 4
```

---

## 12. SYSTEM Instructions

The current implementation recognizes two system instructions.

### WFI

```asm
wfi
```

`WFI` places the CPU into a halt state once the instruction reaches the writeback stage.

The processor remains halted until an interrupt is accepted.

The external status signal is:

```text
cpu_halt = 1
```

---

### MRET

```asm
mret
```

Returns from the interrupt handler.

The processor restores the program counter from the internal `mepc` register.

```text
PC = mepc
```

The ISR state is then cleared.

---

## 13. Unsupported Instructions

The current RTL does not implement the following instruction classes:

* `FENCE`
* `ECALL`
* `EBREAK`
* CSR instructions
* Atomic instructions
* Multiply/divide instructions
* Floating-point instructions
* Compressed instructions

These instructions should not be assumed to execute correctly.

The firmware included in this repository is therefore compiled specifically for:

```text
-march=rv32i
-mabi=ilp32
```

---

## 14. RV32I Register Convention

The processor provides the standard 32 integer registers:

| Register | ABI Name | Description                    |
| -------: | -------- | ------------------------------ |
|       x0 | zero     | Constant zero                  |
|       x1 | ra       | Return address                 |
|       x2 | sp       | Stack pointer                  |
|       x3 | gp       | Global pointer                 |
|       x4 | tp       | Thread pointer                 |
|       x5 | t0       | Temporary                      |
|       x6 | t1       | Temporary                      |
|       x7 | t2       | Temporary                      |
|       x8 | s0/fp    | Saved register / frame pointer |
|       x9 | s1       | Saved register                 |
|      x10 | a0       | Argument / return value        |
|      x11 | a1       | Argument / return value        |
|      x12 | a2       | Argument                       |
|      x13 | a3       | Argument                       |
|      x14 | a4       | Argument                       |
|      x15 | a5       | Argument                       |
|      x16 | a6       | Argument                       |
|      x17 | a7       | Argument                       |
|  x18-x27 | s2-s11   | Saved registers                |
|  x28-x31 | t3-t6    | Temporaries                    |

The RTL enforces:

```text
x0 = 0
```

and prevents writeback to `x0`.
