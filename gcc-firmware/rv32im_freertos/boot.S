// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : boot.S (gcc-firmware/rv32im_freertos)
// Description : Startup at 0x1000_1000: masks interrupts, sets sp/gp/tp and the
//               FreeRTOS trap vector (direct mode), copies .data from its load
//               address, clears .bss, and calls main.
// ============================================================================
    .section .init
    .global _start
_start:
    csrw mie, zero
    csrci mstatus, 8
    la sp, _stack_top
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    mv tp, zero
    la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0
    csrw mscratch, zero

    la t0, __data_load
    la t1, __data_start
    la t2, __data_end
1:
    bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:
    la t1, __bss_start
    la t2, __bss_end
3:
    bgeu t1, t2, 4f
    sw zero, 0(t1)
    addi t1, t1, 4
    j 3b
4:
    call main
    li a0, 2
    tail firmware_fault
