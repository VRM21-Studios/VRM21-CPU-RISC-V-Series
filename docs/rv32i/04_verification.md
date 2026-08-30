# VRM RV32I CPU — Verification

## 1. Verification Overview

The VRM RV32I processor is verified using directed simulation testbenches.

Verification is divided into two levels:

1. Core-level verification
2. SoC-wrapper integration verification

The core-level testbench focuses on CPU datapath and pipeline functionality.

The wrapper-level testbench verifies the interaction between:

* CPU
* Timer
* Interrupt Arbiter
* External RAM
* Interrupt handling
* WFI/MRET flow

---

## 2. Core Testbench

The core testbench is:

```text
tb_vrm_cpu_rv32i_core.v
```

The testbench provides:

* Instruction memory model
* Data memory model
* Clock generation
* Reset generation
* Interrupt stimulus
* On-the-fly instruction encoding
* Self-checking assertions

The memory models use 32-bit words with byte-enable support for data stores.

---

## 3. Instruction Encoding Helpers

The testbench includes helper functions for generating machine instructions:

```text
asm_r()
asm_i()
asm_s()
asm_b()
asm_u()
asm_j()
```

These functions generate 32-bit instruction words according to the corresponding RISC-V instruction formats.

This avoids maintaining a manually encoded instruction image for every test.

---

## 4. ALU Verification

The testbench verifies the following operations.

| Operation | Register | Expected Result |
| --------- | -------- | --------------- |
| ADD       | `x3`     | `5`             |
| SUB       | `x4`     | `25`            |
| SLL       | `x5`     | `0x000000F0`    |
| SLT       | `x6`     | `1`             |
| SLTU      | `x7`     | `0`             |
| XOR       | `x8`     | `0xFFFFFFF9`    |
| SRL       | `x9`     | `0x7FFFFFFB`    |
| SRA       | `x10`    | `0xFFFFFFFB`    |
| OR        | `x11`    | `0xFFFFFFFF`    |
| AND       | `x12`    | `0x00000006`    |

Both signed and unsigned comparison behavior are explicitly tested.

---

## 5. Immediate Generation Verification

The test program verifies immediate handling through:

```asm
lui
addi
```

The expected result is:

```text
x20 = 0x12345678
```

This verifies:

* U-type immediate generation
* I-type immediate generation
* Sign extension
* ALU forwarding between dependent instructions

---

## 6. Load/Store Verification

The core testbench verifies:

```text
SW
LB
LBU
LH
SB
SH
LW
```

The test uses:

```text
0x12345678
```

as a reference data pattern.

The expected memory state after byte and halfword stores is:

```text
DMEM[1] = 0xFFF6000F
```

This verifies:

* Byte enable generation
* Store-byte replication
* Store-halfword replication
* Address offset handling
* Load extraction
* Sign extension
* Zero extension

---

## 7. Load Extraction Verification

For a memory word:

```text
0x12345678
```

the testbench checks:

```text
LB  0(x13) -> 0x00000078
LBU 1(x13) -> 0x00000056
LH  2(x13) -> 0x00001234
```

This verifies that the CPU selects the correct byte or halfword using the address offset.

---

## 8. Hazard Verification

The following sequence is used:

```asm
lw   x14, 0(x13)
addi x15, x14, 1
```

The second instruction depends directly on the result of the load.

The expected result is:

```text
x15 = 0x12345679
```

The test therefore verifies the load-use hazard detector and pipeline stall mechanism.

---

## 9. Forwarding Verification

The test program also contains consecutive dependent ALU instructions.

The forwarding network is expected to correctly select data from:

```text
EX/MEM
```

or:

```text
MEM/WB
```

instead of waiting for the register file writeback.

---

## 10. Branch Flush Verification

A taken branch is tested using:

```asm
beq x1, x1, offset
```

The instruction located immediately after the branch is intentionally written to modify `x16`.

Because the branch is taken, the instruction must be flushed.

Expected result:

```text
x16 = 0
```

A non-zero value indicates an incorrect pipeline flush.

---

## 11. WFI Verification

The core testbench executes:

```asm
wfi
```

and waits for:

```text
cpu_halt == 1
```

The testbench then asserts the interrupt input.

Expected behavior:

1. CPU enters WFI
2. `cpu_halt` becomes asserted
3. Interrupt is applied
4. CPU enters the interrupt vector
5. ISR executes
6. `mret` restores execution
7. CPU resumes normal execution

---

## 12. Interrupt Verification

The interrupt vector is:

```text
0x00000004
```

The testbench places:

```asm
mret
```

at the interrupt vector.

The test verifies that interrupt entry and return do not permanently disrupt normal execution.

---

## 13. Wrapper-Level Verification

The wrapper testbench is:

```text
tb_vrm_cpu_wrapper.v
```

It integrates the following blocks:

```text
vrm_cpu_rv32i_core
vrm_timer
vrm_irq_arbiter
```

The testbench also provides an external RAM model.

---

## 14. Timer Verification

The timer is configured through MMIO.

The test performs:

```text
Timer Compare = 30
Timer Control = 0x7
```

where:

```text
EN         = 1
AUTO_RELOAD = 1
IRQ_EN      = 1
```

The CPU then executes:

```asm
wfi
```

and waits for the timer interrupt.

---

## 15. Interrupt Arbiter Verification

The test enables interrupt source 0:

```text
IRQ_ENABLE[0] = 1
```

The timer interrupt is connected to:

```text
irq_sources[0]
```

The arbiter detects the timer interrupt and forwards it to the CPU.

The ISR then clears the interrupt through the MMIO clear register.

---

## 16. ISR Verification

The interrupt service routine performs:

1. Timer status clear
2. Interrupt arbiter clear
3. External RAM write
4. `MRET`

The external RAM write provides a simple observable marker:

```text
0xABCDE000
```

The testbench checks:

```text
ext_dmem[0] == 0xABCDE000
```

---

## 17. Integration Checks

The wrapper testbench checks:

### CPU wake-up

Expected:

```text
x5 = 99
```

### ISR execution

Expected:

```text
ext_dmem[0] = 0xABCDE000
```

### Interrupt clearing

Expected:

```text
pending = 0
```

These checks verify the complete:

```text
Timer
  |
  v
IRQ Arbiter
  |
  v
CPU IRQ
  |
  v
WFI wake-up
  |
  v
ISR
  |
  v
MRET
```

flow.

---

## 18. Verification Status

The current verification environment is simulation-based.

The core testbench covers:

* Integer ALU operations
* Immediate operations
* Branches
* Jumps
* Loads
* Stores
* Byte enables
* Sign extension
* Zero extension
* Load-use hazards
* Forwarding
* Pipeline flushing
* WFI
* Interrupt entry
* MRET

The wrapper testbench additionally covers:

* MMIO decoding
* Timer operation
* Interrupt arbitration
* W1C behavior
* External memory routing
* ISR execution
* CPU wake-up

---

## 19. FPGA Verification Status

Simulation verification does not by itself constitute FPGA validation.

FPGA testing should be reported separately when an FPGA implementation has been synthesized, implemented, programmed, and exercised on hardware.

Until such testing is performed, the appropriate status is:

```text
Simulation Verified
FPGA Tested: Not Yet
```

This distinction is maintained to avoid treating RTL simulation results as equivalent to physical hardware validation.
