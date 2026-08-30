#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stdint.h>


// ============================================================================
// VRM RV32I SoC - Memory-Mapped Peripheral Definitions
//
// Tier 1 contains system-level peripherals shared by the CPU and accelerator
// subsystem. Application-specific accelerators can be added in Tier 2.
// ============================================================================


// ============================================================================
// TIER 1: SYSTEM CORE PERIPHERALS
// ============================================================================

// ----------------------------------------------------------------------------
// 1. HARDWARE TIMER
//
// Base address : 0x00001000
//
// Register map:
//   +0x00 : Control
//   +0x04 : Compare value
//   +0x08 : Counter value
//   +0x0C : Interrupt status
// ----------------------------------------------------------------------------

#define TIMER_BASE      0x00001000UL

#define TIMER_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x00UL))
#define TIMER_COMPARE   (*(volatile uint32_t *)(TIMER_BASE + 0x04UL))
#define TIMER_COUNTER   (*(volatile uint32_t *)(TIMER_BASE + 0x08UL))
#define TIMER_STATUS    (*(volatile uint32_t *)(TIMER_BASE + 0x0CUL))


// ============================================================================
// 2. INTERRUPT ARBITER
//
// Base address : 0x00002000
//
// Register map:
//   +0x00 : Pending interrupt bits
//   +0x04 : Interrupt enable mask
//   +0x08 : Interrupt clear register (W1C)
// ----------------------------------------------------------------------------

#define IRQ_BASE        0x00002000UL

#define IRQ_PENDING     (*(volatile uint32_t *)(IRQ_BASE + 0x00UL))
#define IRQ_ENABLE      (*(volatile uint32_t *)(IRQ_BASE + 0x04UL))
#define IRQ_CLEAR       (*(volatile uint32_t *)(IRQ_BASE + 0x08UL))


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS
//
// Reserved for DSP, NPU, audio-processing, and other application-specific
// peripherals.
// ============================================================================


#endif /* SOC_MAP_H */
