# RV64IMFD Floating-Point Integration

This directory contains documentation and integration references for the floating-point subsystem used by the VRM21 RV64IMFD processor.

The RV64IMFD implementation uses the separately maintained **VRM21 FPU Series** as its floating-point hardware dependency. The FPU provides the underlying floating-point execution units required by the `F` and `D` extensions.

## FPU Repository

The complete FPU implementation is maintained in a dedicated repository:

**VRM21-FPU-Series**
[VRM21-Studios/VRM21-FPU-Series](https://github.com/VRM21-Studios/VRM21-FPU-Series)

### RTL Implementation

The synthesizable RTL implementation of the FPU functional units is available here:

[VRM21-FPU-Series/rtl](https://github.com/VRM21-Studios/VRM21-FPU-Series/tree/main/rtl)

This directory contains the individual floating-point execution units and supporting RTL used by the FPU.

### Include Files

The FPU constants, definitions, and related include files are maintained here:

[VRM21-FPU-Series/include](https://github.com/VRM21-Studios/VRM21-FPU-Series/tree/main/include)

These files provide the definitions required by the FPU RTL integration.

## Verification Status

The VRM21 FPU Series has been independently verified and validated on FPGA.

This verification status applies to the **FPU repository and its hardware implementation**. It does not imply that the complete RV64IMFD CPU has been FPGA-verified.

The RV64IMFD CPU integration is documented separately, with its verification status based on the CPU-level simulation and hardware validation results.

## Scope

The RV64IMFD CPU uses this FPU as a separately maintained hardware component. Therefore, FPU implementation details, individual functional units, and FPU-specific verification material should be referenced from the VRM21-FPU-Series repository rather than duplicated in this CPU repository.
