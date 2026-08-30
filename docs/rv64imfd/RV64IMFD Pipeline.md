# RV64IMFD Pipeline

## 1. Overview

The RV64IMFD core uses a five-stage pipeline:

```text
IF → ID → EX → MEM → WB
```

The pipeline is controlled dynamically by branch, memory, MDU, FPU, interrupt, and hazard conditions.

---

## 2. Instruction Fetch — IF

The instruction-fetch stage maintains the program counter:

```text
pc
```

The instruction memory interface consists of:

```text
pc_out
instr_in
```

Under normal operation:

```text
PC_next = PC + 4
```

unless a branch, jump, interrupt, or machine return changes the control flow.

The initial reset PC is:

```text
0x0000_0000_0000_4000
```

which corresponds to the beginning of the current main RAM region.

---

## 3. Instruction Decode — ID

The decode stage extracts:

```text
opcode
rd
rs1
rs2
funct3
funct7
```

It also generates the required immediate formats:

```text
I-type
S-type
B-type
U-type
J-type
```

The decoder determines whether an instruction targets:

- Integer ALU
- MDU
- FPU
- Memory
- Branch/jump logic
- System control

---

## 4. Register Read

The ID stage reads from two register files.

### Integer

```text
reg_file[0:31]
```

### Floating Point

```text
freg_file[0:31]
```

The implementation includes writeback bypassing during register reads to reduce unnecessary dependency stalls.

---

## 5. ID/EX Pipeline Register

The ID/EX register captures all information required by the execute stage.

This includes:

- PC
- Integer operands
- Floating-point operands
- Immediate values
- Source register indices
- Destination register index
- Opcode/function fields
- ALU control
- MDU control
- FPU control
- Memory controls
- Branch controls

---

## 6. Execute — EX

The execute stage contains three principal execution paths.

```text
                 +------+
                 | ALU  |
                 +--+---+
                    |
Input ------------>|
                    |
                 +--+---+
                 | MDU  |
                 +--+---+
                    |
                 +--+---+
                 | FPU  |
                 +------+
```

The selected result is forwarded into the EX/MEM pipeline register.

---

## 7. ALU Execution

The ALU handles integer arithmetic and logical operations.

For example:

```text
ADD
SUB
AND
OR
XOR
SLL
SRL
SRA
SLT
SLTU
```

The ALU is also used for:

- Load address calculation
- Store address calculation
- Branch-related arithmetic
- AUIPC
- JAL/JALR address calculations

---

## 8. MDU Execution

The MDU operates as a multi-cycle execution resource for division and remainder operations.

Multiplication can complete through the fast multiplier path.

The CPU uses:

```text
mdu_active
stall_mdu
mdu_valid_out
```

to control the pipeline around the MDU.

During an iterative division, the required pipeline stages are held until the MDU produces a valid result.

---

## 9. FPU Execution

The FPU is treated as a multi-cycle execution resource.

The CPU uses:

```text
fpu_active
stall_fpu
fpu_valid_out
```

to control execution.

The FPU can receive operands from either:

- Floating-point registers
- Integer registers for cross-domain operations

The resulting value is routed either to the floating-point or integer register file depending on the instruction.

---

## 10. Data Forwarding

### Integer Forwarding

Integer operands may be selected from:

```text
EX/MEM
MEM/WB
ID/EX
```

The forwarding control signals are:

```text
forward_a
forward_b
```

### Floating-Point Forwarding

Floating-point operands use:

```text
forward_fa
forward_fb
```

to select recently produced floating-point results.

---

## 11. Load-Use Hazard

A load instruction produces its final register value later than an ALU instruction.

The core detects a dependency through:

```text
stall_load_use
```

When a dependency is detected, the pipeline prevents the dependent instruction from entering execution before the load result is available.

---

## 12. Memory Stall

External memory can indicate that a transaction is still active using:

```text
mem_busy
```

The CPU propagates this condition into:

```text
stall_if_id
stall_ex
stall_mem
```

This prevents pipeline state from advancing while the external memory subsystem is unavailable.

---

## 13. Control Hazard

Branches and jumps are resolved in EX.

A taken control-flow instruction generates:

```text
flush_ex
```

which invalidates the affected pipeline state.

The next PC is selected from:

```text
PC + 4
branch target
jump target
JALR target
MRET target
interrupt vector
```

---

## 14. Store Data Alignment

The EX stage generates:

```text
mem_wdata
mem_wstrb
```

from the store operation.

Supported store widths include:

```text
SB
SH
SW
SD
```

The byte strobe is generated as an 8-bit value for the 64-bit memory interface.

---

## 15. Load Data Extraction

The WB stage extracts the requested data width from the returned 64-bit memory bus.

Supported operations include:

```text
LB
LBU
LH
LHU
LW
LWU
LD
```

The returned value is sign-extended or zero-extended according to the instruction.

---

## 16. Pipeline Freeze Conditions

The primary pipeline freeze conditions are:

```text
load-use hazard
MDU operation
FPU operation
external memory busy
```

The combined control is generated before pipeline registers are updated.

---

## 17. Pipeline Flush Conditions

Pipeline flushing is primarily required for:

```text
taken branch
JAL
JALR
MRET
accepted interrupt
```

The flush mechanism inserts NOP-equivalent state into affected pipeline registers.

---

## 18. Pipeline Status

The pipeline architecture is implemented in RTL.

Verification of all combinations of:

- forwarding
- stalls
- flushes
- multi-cycle operations
- memory latency
- interrupts

remains part of the ongoing verification process.