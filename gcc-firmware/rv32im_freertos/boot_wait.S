// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : boot_wait.S (gcc-firmware/rv32im_freertos)
// Description : Seed image for the legacy boot mode (BOOT_FREERTOS = 0) and for
//               tb_freertos_axi with AXI injection: an endless WFI loop at 0x0.
// ============================================================================
    .section .text
    .global _start
_start:
    wfi
    j _start
