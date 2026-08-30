#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stddef.h>
#include <stdint.h>

/*
 * Volatile register pointer types for 32-bit core peripherals
 * and 64-bit system / accelerator interfaces.
 */
typedef volatile uint32_t* reg32_t;
typedef volatile uint64_t* reg64_t;

// ============================================================================
// TIER 0: SYSTEM CORE PERIPHERALS
// Internal CPU routing; these peripherals do not use the AXI master.
// ============================================================================

// ----------------------------------------------------------------------------
// 1. HARDWARE TIMER
// Base address: 0x0000
// ----------------------------------------------------------------------------

#define TIMER_BASE_ADDR       0x0000000000000000ULL
#define TIMER_CTRL            (*(reg32_t)(TIMER_BASE_ADDR + 0x00))
#define TIMER_COMPARE         (*(reg32_t)(TIMER_BASE_ADDR + 0x04))
#define TIMER_COUNTER         (*(reg32_t)(TIMER_BASE_ADDR + 0x08))
#define TIMER_STATUS          (*(reg32_t)(TIMER_BASE_ADDR + 0x0C))

// ----------------------------------------------------------------------------
// 2. INTERRUPT ARBITER
// Base address: 0x1000
// ----------------------------------------------------------------------------

#define IRQ_BASE_ADDR         0x0000000000001000ULL
#define IRQ_PENDING           (*(reg32_t)(IRQ_BASE_ADDR + 0x00))
#define IRQ_ENABLE            (*(reg32_t)(IRQ_BASE_ADDR + 0x04))
#define IRQ_CLEAR             (*(reg32_t)(IRQ_BASE_ADDR + 0x08))

// ============================================================================
// TIER 1: MAIN DATA MEMORY
// Accessed through the AXI master.
// ============================================================================

#define DMEM_BASE_ADDR        0x0000000000004000ULL

// ============================================================================
// TIER 2: AUDIO SYNTHESIZER CO-PROCESSOR
// Placeholder interface for the VRM Synthesizer Series.
// Accessed through the AXI master.
// ============================================================================

#define OSC_AXI_BASE          0x0000000040000000ULL

/*
 * Register mapping for the synthesizer MMIO interface.
 */

#define OSC_TARGET_PHASE_INC  (*(reg32_t)(OSC_AXI_BASE + 0x00)) // Target phase increment / pitch
#define OSC_AMP_MAX           (*(reg32_t)(OSC_AXI_BASE + 0x10)) // Maximum amplitude
#define OSC_RESET_RUN         (*(reg32_t)(OSC_AXI_BASE + 0x18)) // Phase reset and run control
#define OSC_PACKET_SIZE       (*(reg32_t)(OSC_AXI_BASE + 0x20)) // AXI-Stream TLAST packet size
#define OSC_GEN_MODE          (*(reg32_t)(OSC_AXI_BASE + 0x24)) // Generator mode selector
#define OSC_LFO_WAVE_TYPE     (*(reg32_t)(OSC_AXI_BASE + 0x28)) // LFO waveform type
#define OSC_LFO_PHASE_INC     (*(reg32_t)(OSC_AXI_BASE + 0x2C)) // LFO phase increment / rate
#define OSC_GLIDE_ALPHA       (*(reg32_t)(OSC_AXI_BASE + 0x30)) // Portamento / glide coefficient
#define OSC_SNAP_TO_TARGET    (*(reg32_t)(OSC_AXI_BASE + 0x34)) // Bypass glide and snap directly to target
#define OSC_WAVE_SELECT       (*(reg32_t)(OSC_AXI_BASE + 0x38)) // Wavetable URAM bank selector (0-3)

#endif // SOC_MAP_H
