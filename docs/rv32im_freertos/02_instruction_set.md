# 02 Instruction Set

## Supported Instructions

| Group | Instructions |
| --- | --- |
| U-type | `LUI`, `AUIPC` |
| Jumps | `JAL`, `JALR` |
| Branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Loads | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Stores | `SB`, `SH`, `SW` |
| OP-IMM | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| OP | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| M extension | `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU` |
| Zicsr | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI` |
| System | `ECALL`, `EBREAK`, `MRET`, `WFI` |
| Fence | `FENCE` (decoded as a no-op) |

Division by zero and signed overflow return the results defined by the
M extension. Any other encoding raises an illegal-instruction trap, including
shift-immediates with a wrong funct7 and SYSTEM funct3 = 100.

## Control and Status Registers

| Address | CSR | Notes |
| --- | --- | --- |
| `0x300` | `mstatus` | MIE, MPIE, MPP writable |
| `0x301` | `misa` | reads `0x4000_1100` (RV32, I and M) |
| `0x304` | `mie` | MSIE, MTIE, MEIE writable |
| `0x305` | `mtvec` | base and mode stored; only direct mode is supported |
| `0x340` | `mscratch` | read/write |
| `0x341` | `mepc` | 4-byte aligned |
| `0x342` | `mcause` | interrupt bit and cause code |
| `0x343` | `mtval` | read/write |
| `0x344` | `mip` | read-only, MSIP/MTIP/MEIP from the interrupt lines |
| `0xB00` | `mcycle` | lower 32 bits, read-only |
| `0xB02` | `minstret` | lower 32 bits, read-only |
| `0xF11`–`0xF14` | IDs | read 0 |

An access to any other CSR address raises an illegal-instruction trap.

## Traps

| Cause | mcause | mtval |
| --- | --- | --- |
| Illegal instruction | 2 | instruction encoding |
| Illegal CSR address | 2 | CSR address |
| EBREAK | 3 | 0 |
| ECALL | 11 | 0 |
| Machine software interrupt (MSIP) | `0x8000_0003` | 0 |
| Machine timer interrupt (MTIP) | `0x8000_0007` | 0 |
| Machine external interrupt (MEIP) | `0x8000_000B` | 0 |

Interrupt priority is MEIP, then MTIP, then MSIP. MTIP comes directly from
the local timer; MEIP is the output of the interrupt arbiter. The software
interrupt input is tied low in this SoC.

## Reduced Scope

- Machine mode only. MRET writes MPP = 00 although no lower privilege mode
  exists.
- `mcycleh`, `minstreth`, and counter writes are not implemented.
- Misaligned loads and stores do not trap.
- The trap target is `mtvec` including its mode bits; firmware must use
  direct mode (`mtvec[1:0] = 00`).
- No compressed instructions, no atomics, no floating point.
- The RISC-V architecture test suite has not been run on this core.
