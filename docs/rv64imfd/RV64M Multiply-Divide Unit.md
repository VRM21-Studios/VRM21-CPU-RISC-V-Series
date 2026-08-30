# RV64M Multiply/Divide Unit

## 1. Overview

The RV64M Multiply/Divide Unit is implemented by:

```text
vrm_mdu_rv64m
```

The unit provides the arithmetic operations defined by the RISC-V `M` extension.

---

## 2. Supported Operations

### 64-bit Operations

```text
MUL
MULH
MULHSU
MULHU

DIV
DIVU
REM
REMU
```

### 32-bit Word Operations

```text
MULW

DIVW
DIVUW

REMW
REMUW
```

---

## 3. Operation Encoding

The CPU provides the MDU with:

```text
mdu_op[3:0]
```

where:

```text
mdu_op[3]   = word operation
mdu_op[2:0] = funct3
```

This allows the same MDU block to service both XLEN=64 and W-form operations.

---

## 4. Multiplier

The multiplier uses a wide signed multiplication datapath:

```text
64/65-bit × 64/65-bit
```

The implementation contains:

```text
(* use_dsp = "yes" *)
```

to encourage FPGA DSP resource inference in supported synthesis environments.

The required result portion is selected according to the operation:

```text
MUL
MULH
MULHSU
MULHU
```

Word operations use the lower 32-bit operands and produce the architecturally required sign-extended result.

---

## 5. Divider

Normal division uses an iterative radix-2 algorithm.

The divider maintains:

```text
div_rq
div_b
div_count
```

The quotient and remainder are generated iteratively rather than through a single large combinational divider.

The nominal iteration count is:

```text
32 cycles for word operations
64 cycles for full-width operations
```

---

## 6. Signedness

The MDU derives operand signedness from the operation type.

Signed operations use two's-complement absolute values internally.

After division, the quotient and remainder are restored to the required architectural sign.

---

## 7. Division by Zero

Division by zero is handled without entering the iterative divider.

For division:

```text
DIV / DIVU
DIVW / DIVUW
```

the result is generated using the RISC-V architectural behavior.

For remainder operations:

```text
REM / REMU
REMW / REMUW
```

the dividend is returned according to the architectural rule.

This creates a fast path that avoids unnecessary divider iterations.

---

## 8. Signed Overflow

The signed division overflow case:

```text
INT_MIN / -1
```

is detected before the iterative divider starts.

The quotient and remainder are generated directly according to the RISC-V architectural definition.

This applies independently to:

```text
RV64
RV32 word operations
```

---

## 9. Handshake

The MDU uses:

```text
valid_in
valid_out
busy
```

to communicate operation state with the CPU.

The CPU stalls the pipeline while an MDU instruction is still active.

---

## 10. CPU Integration

The CPU tracks MDU execution using:

```text
mdu_active
stall_mdu
mdu_valid_in
mdu_valid_out
```

The MDU result is selected as the EX-stage result when the current instruction is an MDU instruction.

---

## 11. Verification Focus

MDU verification should cover:

### Multiplication

- Zero operands
- Maximum positive values
- Negative operands
- Mixed signed/unsigned operands
- High-half extraction
- Word operations

### Division

- Positive/positive
- Positive/negative
- Negative/positive
- Negative/negative
- Division by zero
- Signed overflow
- Word operations
- Remainder sign behavior

---

## 12. Current Status

The MDU RTL is implemented.

Simulation verification and integration testing are ongoing.

FPGA implementation status should be evaluated separately from RTL simulation.