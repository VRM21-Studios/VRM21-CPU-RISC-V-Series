`ifndef VRM_SOC_MAP_RV32I_VH
`define VRM_SOC_MAP_RV32I_VH

// ============================================================================
// MODULE: VRM SoC Memory Map
// DESCRIPTION:
// Memory-map definitions for the VRM RV32I-based SoC.
//
// The address space is organized into two main tiers:
// - Tier 1 : System core peripherals and memory
// - Tier 2 : Application-specific accelerators
//
// This header file contains address definitions only. It does not implement
// any hardware logic.
//
// Address regions are defined using BASE_ADDR and SIZE parameters. The
// corresponding END_ADDR is calculated automatically as BASE_ADDR + SIZE.
// ============================================================================


// ============================================================================
// TIER 1: SYSTEM CORE
// ----------------------------------------------------------------------------
// Low-address region reserved for fundamental system resources such as RAM,
// timers, and interrupt control.
// ============================================================================


// ----------------------------------------------------------------------------
// 0. SYSTEM RAM
// ----------------------------------------------------------------------------
// Main system memory region.
//
// Current configuration:
// - Base address : 0x0000_0000
// - Size         : 4 KB
// ----------------------------------------------------------------------------

`define RAM_BASE_ADDR   32'h0000_0000
`define RAM_SIZE        32'h0000_1000
`define RAM_END_ADDR    (`RAM_BASE_ADDR + `RAM_SIZE)


// ----------------------------------------------------------------------------
// 1. HARDWARE TIMER
// ----------------------------------------------------------------------------
// Memory-mapped hardware timer peripheral.
//
// Register map:
//   BASE + 0x00 : Control register
//   BASE + 0x04 : Compare value
//   BASE + 0x08 : Counter value
//   BASE + 0x0C : Interrupt status
//
// CTRL register:
//   Bit 0 : Timer Enable
//   Bit 1 : Auto Reload
//   Bit 2 : Interrupt Enable
//
// STATUS register:
//   Bit 0 : Interrupt Pending
//           W1C (Write 1 to Clear)
//
// The timer peripheral occupies a 256-byte address region.
// ----------------------------------------------------------------------------

`define TIMER_BASE_ADDR 32'h0000_1000

`define TIMER_CTRL      32'h0000_0000
`define TIMER_COMPARE   32'h0000_0004
`define TIMER_COUNTER   32'h0000_0008
`define TIMER_STATUS    32'h0000_000C

`define TIMER_SIZE      32'h0000_0100
`define TIMER_END_ADDR  (`TIMER_BASE_ADDR + `TIMER_SIZE)


// ----------------------------------------------------------------------------
// 2. INTERRUPT ARBITER
// ----------------------------------------------------------------------------
// Central interrupt controller for the RV32I system.
//
// The arbiter collects interrupt sources, stores pending interrupt status,
// applies per-source enable masking, and generates the interrupt request
// delivered to the CPU.
//
// Register map:
//   BASE + 0x00 : Pending register
//   BASE + 0x04 : Enable register
//   BASE + 0x08 : Clear register
//
// PENDING register:
//   Read-only interrupt pending status.
//
// ENABLE register:
//   Read/write interrupt mask.
//   Bit = 1 : Interrupt source enabled.
//   Bit = 0 : Interrupt source disabled.
//
// CLEAR register:
//   W1C (Write 1 to Clear).
//   Writing a '1' clears the corresponding pending interrupt.
//
// The interrupt arbiter occupies a 256-byte address region.
// ----------------------------------------------------------------------------

`define IRQ_BASE_ADDR   32'h0000_2000

`define IRQ_REG_PENDING 32'h0000_0000
`define IRQ_REG_ENABLE  32'h0000_0004
`define IRQ_REG_CLEAR   32'h0000_0008

`define IRQ_SIZE        32'h0000_0100
`define IRQ_END_ADDR    (`IRQ_BASE_ADDR + `IRQ_SIZE)


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS
// ----------------------------------------------------------------------------
// Higher address space reserved for application-specific hardware such as
// DSP, NPU, audio processing, and other accelerator peripherals.
//
// Additional peripheral mappings can be added here without modifying the
// system-core address definitions above.
// ============================================================================


// ============================================================================
// END OF MEMORY MAP
// ============================================================================

`endif
