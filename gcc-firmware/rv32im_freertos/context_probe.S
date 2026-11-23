// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : context_probe.S (gcc-firmware/rv32im_freertos)
// Description : Register-preservation probe run by the REG task. Holds known
//               values in s2/t3/a4 and repeats DIV/REM until the tick counter
//               reaches a target; returns 1 if a value was corrupted across a
//               context switch or the stack is not 16-byte aligned, else 0.
// ============================================================================
    .section .text.context_probe,"ax",@progbits
    .global context_probe
context_probe:
    andi t0, sp, 15
    bnez t0, 2f
    addi sp, sp, -16
    sw s2, 0(sp)
    li s2, 0x32123456
    li t3, 0x98765432
    li a4, 0x5a5affff
1:
    li t0, 0x32123456
    bne s2, t0, 3f
    li t0, 0x98765432
    bne t3, t0, 3f
    li t0, 0x5a5affff
    bne a4, t0, 3f
    li a5, 123456
    li a6, 97
    div t4, a5, a6
    li t0, 1272
    bne t4, t0, 3f
    rem t5, a5, a6
    li t0, 72
    bne t5, t0, 3f
    lw t0, 0(a0)
    bltu t0, a1, 1b
    li a0, 0
    j 4f
2:
    li a0, 1
    ret
3:
    li a0, 1
4:
    lw s2, 0(sp)
    addi sp, sp, 16
    ret
