# VRM-RV32I CPU — Testbench Simulation Results

## 1. Overview

This document defines the expected Vivado Simulator console output for the RV32I CPU testbenches.

Two simulation levels are covered:

1. `tb_vrm_cpu_rv32i_core`

   * Verifies the standalone RV32I processor core.
   * Covers ALU operations, immediate operations, load/store instructions, byte-enable behavior, load-use hazards, branch flushing, WFI, interrupt entry, and MRET recovery.

2. `tb_vrm_cpu_wrapper`

   * Verifies the RV32I CPU wrapper and its integrated system peripherals.
   * Covers MMIO routing, hardware timer operation, interrupt arbitration, WFI wake-up, ISR execution, W1C interrupt clearing, and external RAM access.

The console output below represents the expected result when the simulations complete successfully.

---

## 2. Core-Level Testbench

### Testbench

```text
tb_vrm_cpu_rv32i_core
```

### Verification Scope

The standalone CPU testbench verifies:

* LUI and ADDI execution
* Integer ALU operations
* Signed and unsigned comparisons
* Logical and arithmetic shifts
* Load/store operations
* Byte-enable generation
* Signed and unsigned byte/halfword extraction
* Load-use hazard handling
* Branch resolution and pipeline flushing
* WFI halt behavior
* Interrupt entry
* MRET execution
* Post-interrupt execution recovery

### Expected Vivado Console Output

A successful simulation is expected to produce output similar to:

```text
[INFO] Time: <time> - CPU is HALTED (WFI). Firing NPU Interrupt...

=============================================
    VRM CPU RV32I - ULTIMATE TEST RESULTS
=============================================
[PASS] ALU ADD  -> x3 = 00000005
[PASS] ALU SUB  -> x4 = 00000019
[PASS] ALU SLL  -> x5 = 000000f0
[PASS] ALU SLT  -> x6 = 00000001
[PASS] ALU SLTU -> x7 = 00000000
[PASS] ALU XOR  -> x8 = fffffff9
[PASS] ALU SRL  -> x9 = 7ffffffb
[PASS] ALU SRA  -> x10= fffffffb
[PASS] ALU OR   -> x11= ffffffff
[PASS] ALU AND  -> x12= 00000006
[PASS] LUI+ADDI -> x20 = 12345678
[PASS] SW (Word)-> DMEM[0] = 12345678
[PASS] LB (S.E) -> x21 = 00000078
[PASS] LBU (Z.E)-> x22 = 00000056
[PASS] LH (S.E) -> x23 = 00001234
[PASS] SB & SH  -> DMEM[1] = fff6000f
[PASS] MEM HAZARD FORWARDING -> x15= 12345679
[PASS] BRANCH FLUSH -> x16 remains 00000000
[PASS] WFI WAKEUP & MRET -> x17= 00000777
=============================================

$finish called at time <time>
```

The exact timestamp is simulator-dependent and is therefore represented as `<time>`.

---

## 3. Core-Level Pass Criteria

The simulation is considered successful when all verification checks report `[PASS]`.

### ALU Verification

| Test |    Expected Result |
| ---- | -----------------: |
| ADD  |  `x3 = 0x00000005` |
| SUB  |  `x4 = 0x00000019` |
| SLL  |  `x5 = 0x000000F0` |
| SLT  |  `x6 = 0x00000001` |
| SLTU |  `x7 = 0x00000000` |
| XOR  |  `x8 = 0xFFFFFFF9` |
| SRL  |  `x9 = 0x7FFFFFFB` |
| SRA  | `x10 = 0xFFFFFFFB` |
| OR   | `x11 = 0xFFFFFFFF` |
| AND  | `x12 = 0x00000006` |

### Memory Verification

| Test       |        Expected Result |
| ---------- | ---------------------: |
| LUI + ADDI |     `x20 = 0x12345678` |
| SW         | `DMEM[0] = 0x12345678` |
| LB         |     `x21 = 0x00000078` |
| LBU        |     `x22 = 0x00000056` |
| LH         |     `x23 = 0x00001234` |
| SB + SH    | `DMEM[1] = 0xFFF6000F` |

### Pipeline and Interrupt Verification

| Test                       | Expected Result             |
| -------------------------- | --------------------------- |
| Load-use hazard            | `x15 = 0x12345679`          |
| Branch flush               | `x16 = 0x00000000`          |
| WFI wake-up                | CPU leaves halt state       |
| MRET                       | Execution resumes correctly |
| Post-interrupt instruction | `x17 = 0x00000777`          |

No `[FAIL]` message should be present in a successful run.

---

## 4. Wrapper-Level Integration Testbench

### Testbench

```text
tb_vrm_cpu_wrapper
```

### Verification Scope

The wrapper-level testbench verifies the integration between:

* `vrm_cpu_rv32i_core`
* `vrm_timer`
* `vrm_irq_arbiter`
* MMIO address decoder
* External data memory interface

The test sequence configures the timer, enables the corresponding interrupt source, places the CPU into WFI, and verifies that the timer-generated interrupt wakes the CPU.

The interrupt service routine subsequently:

1. Clears the timer interrupt status.
2. Clears the corresponding interrupt arbiter pending bit.
3. Writes a verification value to external RAM.
4. Executes `MRET`.

---

## 5. Expected Wrapper Console Output

A successful simulation is expected to produce output similar to:

```text
[INFO] Starting SoC Wrapper Test...
[INFO] Waiting for CPU to enter WFI state...
[INFO] Time: <time> - CPU is sleeping (WFI). Hardware Timer is running...
[INFO] Time: <time> - CPU Woke Up! Executing ISR to clear interrupts...

=============================================
   VRM SoC WRAPPER - INTEGRATION RESULTS
=============================================
[PASS] CPU successfully woke up from WFI
[PASS] MMIO & ISR Execution: Ext RAM Flag written successfully
[PASS] Arbiter IRQ successfully cleared (W1C)
=============================================

$finish called at time <time>
```

The exact timestamps depend on simulator scheduling and are not part of the functional verification criteria.

---

## 6. Wrapper-Level Pass Criteria

### CPU Wake-Up

The CPU must leave the WFI halt state after the timer generates an enabled interrupt.

Expected result:

```text
[PASS] CPU successfully woke up from WFI
```

The corresponding register value is:

```text
x5 = 99 = 0x00000063
```

This value is written by the instruction executed after interrupt recovery and serves as the software-visible indication that execution successfully continued after WFI.

---

### ISR and External Memory Access

The ISR writes:

```text
0xABCDE000
```

to external RAM address:

```text
0x00000000
```

Expected result:

```text
[PASS] MMIO & ISR Execution: Ext RAM Flag written successfully
```

Expected memory contents:

```text
ext_dmem[0] = 32'hABCDE000
```

---

### Interrupt Arbiter W1C

The ISR writes `1` to the arbiter clear register at:

```text
IRQ_BASE + 0x08
```

which corresponds to:

```text
0x00002008
```

The pending interrupt state must subsequently become zero.

Expected result:

```text
[PASS] Arbiter IRQ successfully cleared (W1C)
```

Expected internal state:

```text
uut.sys_arbiter.pending = 32'h00000000
```

---

## 7. Combined Expected Verification Summary

When both testbenches complete successfully, the RV32I CPU series has demonstrated the following functional capabilities:

```text
RV32I CPU Core
├── Integer ALU
│   ├── ADD / SUB
│   ├── AND / OR / XOR
│   ├── SLL / SRL / SRA
│   └── SLT / SLTU
│
├── Immediate Instructions
│   ├── ADDI
│   ├── SLTI / SLTIU
│   ├── ANDI / ORI / XORI
│   └── SLLI / SRLI / SRAI
│
├── Upper Immediate Instructions
│   ├── LUI
│   └── AUIPC
│
├── Control Flow
│   ├── Conditional Branch
│   ├── JAL
│   ├── JALR
│   └── Pipeline Flush
│
├── Memory Access
│   ├── LB / LBU
│   ├── LH / LHU
│   ├── LW
│   ├── SB
│   ├── SH
│   └── SW
│
├── Pipeline Control
│   ├── Load-Use Hazard Detection
│   ├── EX Forwarding
│   └── WB-to-ID Forwarding
│
├── Interrupt Support
│   ├── IRQ Entry
│   ├── Interrupt Vector
│   ├── MRET
│   └── WFI
│
└── SoC Integration
    ├── MMIO Address Decode
    ├── Hardware Timer
    ├── Interrupt Arbiter
    ├── W1C Interrupt Handling
    └── External Memory Interface
```

---

## 8. Expected Simulation Status

The final expected status for both testbenches is:

```text
CORE TESTBENCH      : PASS
WRAPPER TESTBENCH   : PASS
OVERALL STATUS      : PASS
```

A successful simulation must terminate normally through `$finish` without functional `[FAIL]` messages.

---

## 9. Notes

### 9.1 Timestamp Variations

The timestamps printed by `$display` depend on:

* Clock period
* Reset release timing
* Pipeline latency
* Simulator scheduling
* Instruction execution timing

Therefore, timestamps are intentionally not treated as fixed verification values.

### 9.2 Console Formatting

The exact spacing of messages may vary slightly between Vivado versions and simulator configurations. Functional verification is based on the `[PASS]` / `[FAIL]` result and the associated register or memory value.

### 9.3 Simulation vs. FPGA Verification

These results represent RTL simulation only.

A successful simulation does not by itself constitute FPGA hardware validation. FPGA verification should be performed separately using the intended Vivado synthesis, implementation, bitstream generation, and hardware test flow.

### 9.4 Testbench Role

The testbenches are intended to provide functional regression coverage for the RV32I CPU series before integration with larger VRM21 SoC and DSP designs.

---

## 10. Result Interpretation

A fully successful run should contain:

```text
No [FAIL] messages
All expected [PASS] messages
Normal simulation termination
```

The two testbenches together provide coverage from the processor datapath and pipeline level through the peripheral and interrupt integration level.
