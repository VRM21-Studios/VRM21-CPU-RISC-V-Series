// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : byte_enable.S (tb/rv32im_freertos/programs)
// Description : SB/SH lane preservation and LB/LBU/LH/LHU extension checks.
// ============================================================================
    .section .text
    .globl _start
_start:
    li t0, 0x10001000
    li t1, 0x11223344
    sw t1, 0(t0)
    li t1, 0x55667788
    sw t1, 4(t0)

    li t1, 0xa5
    sb t1, 1(t0)
    lw t2, 0(t0)
    sw t2, 16(t0)
    lb t2, 1(t0)
    sw t2, 20(t0)
    lbu t2, 1(t0)
    sw t2, 24(t0)

    li t1, 0xbeef
    sh t1, 2(t0)
    lh t2, 2(t0)
    sw t2, 28(t0)
    lhu t2, 2(t0)
    sw t2, 32(t0)
    lw t2, 0(t0)
    sw t2, 36(t0)
    lw t2, 4(t0)
    sw t2, 40(t0)

    li t1, 0xdeadbeef
    sw t1, 44(t0)
loop:
    j loop
