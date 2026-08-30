# RV64F/D Floating-Point Integration

## 1. Overview

The RV64IMFD CPU integrates the VRM21 floating-point subsystem through:

```text
vrm_fpu_rv64fd
```

The CPU-level wrapper is responsible for instruction routing and register-domain integration.

The internal floating-point implementation is maintained separately in:

**VRM21-FPU-Series**

---

## 2. CPU/FPU Interface

The CPU provides:

```text
valid_in
fpu_op
funct3
op_a
op_b
```

and receives:

```text
result_out
valid_out
```

The interface allows the FPU to operate as a multi-cycle execution resource.

---

## 3. Functional Lanes

The FPU wrapper contains dedicated functional lanes for:

```text
ADD/SUB
MUL
DIV
SQRT
CONVERSION
MISC
MATH
```

The wrapper selects the appropriate lane based on the decoded operation.

---

## 4. CPU Instruction Routing

Floating-point instructions use opcode:

```text
0x53
```

The CPU decoder translates the instruction encoding into an internal:

```text
fpu_op[3:0]
```

selection.

The current mapping includes:

```text
FADD   → operation 0
FSUB   → operation 1
FMUL   → operation 2
FDIV   → operation 3
FSQRT  → operation 4
FCVT   → operation 6
FMV/FCLASS → operation 7
MATH   → operation 8
```

---

## 5. Floating-Point Register Routing

Normal floating-point operations read from:

```text
freg_file
```

Cross-domain instructions can instead obtain operands from:

```text
reg_file
```

The CPU identifies two primary routing directions:

```text
GPR → FPU
FPU → GPR
```

---

## 6. GPR to FPU

Integer-to-floating operations and floating-point register moves can use the integer forwarding path.

The CPU therefore selects:

```text
fwd_rs1_data
```

instead of the normal floating-point source when required.

---

## 7. FPU to GPR

Operations producing an integer result from the FPU are routed through:

```text
fpu_result_out
```

and eventually selected by:

```text
mem_wb_fpu_to_gpr
```

during writeback.

---

## 8. Floating-Point Forwarding

Floating-point dependencies are handled through dedicated forwarding signals:

```text
forward_fa
forward_fb
```

The forwarding sources include:

```text
EX/MEM FPU result
MEM/WB FPU result
ID/EX floating-point register value
```

---

## 9. FLW NaN-Boxing

The CPU implements NaN-boxing for 32-bit floating-point loads.

When an `FLW`-style 32-bit floating-point value is loaded into the 64-bit floating-point register file, the upper half is filled according to the required NaN-boxing representation.

The current implementation uses:

```text
32'hFFFF_FFFF
```

for the upper 32 bits.

---

## 10. FPU Stall Handling

The FPU is treated as a potentially multi-cycle execution resource.

The CPU tracks:

```text
fpu_active
fpu_valid_in
fpu_valid_out
stall_fpu
```

The pipeline remains stalled until the FPU reports a valid result.

---

## 11. Dedicated FPU Repository

The CPU repository intentionally does not duplicate the detailed implementation of the FPU functional units.

The internal FPU RTL and associated support files are maintained in:

```text
VRM21-FPU-Series/
├── rtl/
└── include/
```

This separation allows the FPU to evolve independently from the CPU integration layer.

---

## 12. Verification

FPU verification is performed at multiple levels:

```text
FPU unit level
      ↓
FPU wrapper level
      ↓
CPU/FPU integration
      ↓
RV64IMFD firmware execution
```

The CPU integration should be considered verified only after the complete test environment covers both the FPU and the CPU-side routing.

---

## 13. Current Status

The FPU integration is implemented in RTL.

The dedicated FPU subsystem and CPU integration remain under verification.

Complete IEEE-754 and RISC-V floating-point compliance is not claimed until the corresponding verification coverage has been completed.