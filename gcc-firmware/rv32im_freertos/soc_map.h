#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stdint.h>


// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : soc_map.h (gcc-firmware/rv32im_freertos)
// Description : CPU-side memory map of the RV32IM + VCF + FreeRTOS SoC.
//               Must stay consistent with include/rv32im_freertos/vrm_soc_map_rv32i.vh.
// ============================================================================


// ============================================================================
// TIER 0: SYSTEM MEMORY
// ============================================================================

#define ROM_BASE        0x00000000UL
#define ROM_SIZE        0x00001000UL
#define ROM_END         (ROM_BASE + ROM_SIZE)

#define RAM_BASE        0x10000000UL
#define RAM_SIZE        0x00010000UL
#define RAM_END         (RAM_BASE + RAM_SIZE)


// ============================================================================
// TIER 1: SYSTEM CORE PERIPHERALS
// ============================================================================

#define TIMER_BASE      0x40000000UL

#define TIMER_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x00UL))
#define TIMER_COMPARE   (*(volatile uint32_t *)(TIMER_BASE + 0x04UL))
#define TIMER_COUNTER   (*(volatile uint32_t *)(TIMER_BASE + 0x08UL))
#define TIMER_STATUS    (*(volatile uint32_t *)(TIMER_BASE + 0x0CUL))


#define IRQ_BASE        0x40001000UL

#define IRQ_PENDING     (*(volatile uint32_t *)(IRQ_BASE + 0x00UL))
#define IRQ_ENABLE      (*(volatile uint32_t *)(IRQ_BASE + 0x04UL))
#define IRQ_CLEAR       (*(volatile uint32_t *)(IRQ_BASE + 0x08UL))


// ============================================================================
// MACHINE-MODE CSR FIELD DEFINITIONS
// ============================================================================
//
// These mirror the WARL-legal bit positions implemented by vrm_csr.
// Bits outside these masks are read-only / hardwired.
// ============================================================================

// ---- mstatus (0x300) ----
#define MSTATUS_MIE     (1UL << 3)      // Machine Interrupt Enable
#define MSTATUS_MPIE    (1UL << 7)      // Machine Previous Interrupt Enable
#define MSTATUS_MPP     (3UL << 11)     // Machine Previous Privilege

// ---- mie (0x304) ----
#define MIE_MSIE        (1UL << 3)      // Machine Software Interrupt Enable
#define MIE_MTIE        (1UL << 7)      // Machine Timer    Interrupt Enable
#define MIE_MEIE        (1UL << 11)     // Machine External Interrupt Enable

// ---- mip (0x344) ---- (read-only mirror of irq lines)
#define MIP_MSIP        (1UL << 3)
#define MIP_MTIP        (1UL << 7)
#define MIP_MEIP        (1UL << 11)


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS – Wavetable Oscillator (RESERVED)
// ============================================================================
// The oscillator is not instantiated in the audio-effects SoC. The window is
// kept reserved so it is never reassigned. Do not access it from firmware:
// writes are ignored and reads return 0.

#define OSC_BASE        0x80001000UL    // reserved, inactive


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS – VCF (Chamberlin SVF, stereo)
// ============================================================================
// Commit protocol:
//   - CUTOFF / RES / LCO are shadow registers; ftype is CTRL-resident.
//   - Every register write cancels a pending commit; a CTRL write with
//     bit 2 set arms it. Write the shadows first, CTRL with commit LAST.
//   - Hardware copies shadow -> active per channel at the first zero crossing
//     after the arm (or after the ZCD timeout), fire-and-forget. No polling
//     required. CTRL bit 31 reads 1 while the commit is still armed.

#define VCF_BASE        0x80002000UL

#define VCF_CTRL        (*(volatile uint32_t *)(VCF_BASE + 0x00UL))
#define VCF_CUTOFF      (*(volatile uint32_t *)(VCF_BASE + 0x04UL))   // Q1.15
#define VCF_RES         (*(volatile uint32_t *)(VCF_BASE + 0x08UL))   // Q1.15
#define VCF_LCO         (*(volatile uint32_t *)(VCF_BASE + 0x0CUL))   // unsigned

// ---- CTRL fields ----
#define VCF_CTRL_ENABLE         (1UL << 0)      // 0 = zero-latency bypass
#define VCF_CTRL_COMMIT         (1UL << 2)      // arm commit (L + R)
#define VCF_CTRL_FTYPE_SHIFT    3
#define VCF_CTRL_FTYPE_MASK     (3UL << VCF_CTRL_FTYPE_SHIFT)
#define VCF_CTRL_STATUS         (1UL << 31)     // read-only: commit still armed

#define VCF_FTYPE_LP            0UL
#define VCF_FTYPE_HP            1UL
#define VCF_FTYPE_BP            2UL

#define VCF_CTRL_WORD(en, ftype, commit) \
    ( ((en)     ? VCF_CTRL_ENABLE : 0UL) | \
      ((commit) ? VCF_CTRL_COMMIT : 0UL) | \
      (((uint32_t)(ftype) << VCF_CTRL_FTYPE_SHIFT) & VCF_CTRL_FTYPE_MASK) )

// Enable + LP + commit = 5
#define VCF_CTRL_ON_LP          VCF_CTRL_WORD(1, VCF_FTYPE_LP, 1)
// Bypass, ftype LP, no commit = 0
#define VCF_CTRL_OFF_LP         VCF_CTRL_WORD(0, VCF_FTYPE_LP, 0)

#endif /* SOC_MAP_H */