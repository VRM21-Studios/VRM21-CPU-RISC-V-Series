#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stdint.h>


// ============================================================================
// VRM RV32I SoC Memory Map
// ----------------------------------------------------------------------------
// Address-space organization:
//
//   Tier 0 : System memory
//            - Boot ROM
//            - System RAM
//
//   Tier 1 : System core peripherals
//            - Hardware timer
//            - Interrupt arbiter
//
//   Tier 2 : Application-specific accelerators
// ============================================================================


// ============================================================================
// TIER 0: SYSTEM MEMORY
// ============================================================================

// ----------------------------------------------------------------------------
// BOOT ROM
// ----------------------------------------------------------------------------

#define ROM_BASE        0x00000000UL
#define ROM_SIZE        0x00001000UL
#define ROM_END         (ROM_BASE + ROM_SIZE)


// ----------------------------------------------------------------------------
// SYSTEM RAM
// ----------------------------------------------------------------------------

#define RAM_BASE        0x10000000UL
#define RAM_SIZE        0x00010000UL
#define RAM_END         (RAM_BASE + RAM_SIZE)


// ============================================================================
// TIER 1: SYSTEM CORE PERIPHERALS
// ============================================================================

// ----------------------------------------------------------------------------
// HARDWARE TIMER
// ----------------------------------------------------------------------------
//
// Base address : 0x40000000
//
// Register map:
//   +0x00 : Control register
//   +0x04 : Compare value
//   +0x08 : Counter value
//   +0x0C : Interrupt status
// ----------------------------------------------------------------------------

#define TIMER_BASE      0x40000000UL

#define TIMER_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x00UL))
#define TIMER_COMPARE   (*(volatile uint32_t *)(TIMER_BASE + 0x04UL))
#define TIMER_COUNTER   (*(volatile uint32_t *)(TIMER_BASE + 0x08UL))
#define TIMER_STATUS    (*(volatile uint32_t *)(TIMER_BASE + 0x0CUL))


// ----------------------------------------------------------------------------
// INTERRUPT ARBITER
// ----------------------------------------------------------------------------
//
// Base address : 0x40001000
//
// Register map:
//   +0x00 : Pending interrupt register
//   +0x04 : Interrupt enable register
//   +0x08 : Interrupt clear register
// ----------------------------------------------------------------------------

#define IRQ_BASE        0x40001000UL

#define IRQ_PENDING     (*(volatile uint32_t *)(IRQ_BASE + 0x00UL))
#define IRQ_ENABLE      (*(volatile uint32_t *)(IRQ_BASE + 0x04UL))
#define IRQ_CLEAR       (*(volatile uint32_t *)(IRQ_BASE + 0x08UL))


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS
// ----------------------------------------------------------------------------
// Reserved for future application-specific peripherals.
//
// Possible applications include:
//   - DSP accelerators
//   - Audio processing hardware
//   - NPU / AI accelerators
//   - Custom memory-mapped peripherals
// ============================================================================


// ----------------------------------------------------------------------------
// DSP ACCELERATOR TEMPLATE
// ----------------------------------------------------------------------------
//
// Example placeholder:
//
// #define DSP_BASE       0x80000000UL
// #define DSP_SIZE       0x00000100UL
// #define DSP_END        (DSP_BASE + DSP_SIZE)
//
// Register definitions should be added when a specific DSP accelerator is
// integrated into the system.
// ----------------------------------------------------------------------------


#endif /* SOC_MAP_H */
