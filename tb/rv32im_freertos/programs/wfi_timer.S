// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : wfi_timer.S (tb/rv32im_freertos/programs)
// Description : Timer wake from WFI. Built twice: with MIE = 1 (trap taken,
//               mepc/mcause stored) and with -DMASKED (MIE = 0, wake without trap).
// ============================================================================
    .section .text
    .globl _start
_start:
    li t0, 0x40000000
    li s0, 0x10001000
    la t2, trap
    csrw mtvec, t2
    li t2, 0x80
    csrw mie, t2
#ifndef MASKED
    csrsi mstatus, 8
#endif
    li s1, 0
    li s2, 0
    sw zero, 8(t0)
    li t2, 150
    sw t2, 4(t0)
    li t2, 5
    sw t2, 0(t0)
    li t1, 0x123
    sw t1, 8(s0)
    wfi
resume:
#ifndef MASKED
    nop
#endif
    sw t1, 0(t0)
    lw t2, 8(s0)
    bne t2, t1, fail
    csrr t2, mie
    andi t2, t2, 0x80
    beqz t2, fail
    sw s1, 0(s0)
    sw s2, 4(s0)
    la t2, resume
    sw t2, 12(s0)
    li t2, 0xdeadbeef
    sw t2, 44(s0)
loop:
    j loop
fail:
    li t2, 0xbad
    sw t2, 44(s0)
    j loop
    .balign 4
trap:
    csrr s1, mepc
    csrr s2, mcause
    sw zero, 0(t0)
    li t3, 1
    sw t3, 12(t0)
    mret
