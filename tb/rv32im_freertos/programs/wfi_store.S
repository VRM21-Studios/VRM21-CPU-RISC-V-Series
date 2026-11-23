// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : wfi_store.S (tb/rv32im_freertos/programs)
// Description : WFI without a wake source; the store after WFI must not execute.
// ============================================================================
    .section .text
    .globl _start
_start:
    li t0, 0x40000000
    li t1, 0x123
    wfi
    nop
    sw t1, 0(t0)
loop:
    j loop
