`ifndef VRM_SOC_MAP_RV32I_VH
`define VRM_SOC_MAP_RV32I_VH

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
//            - Reserved for DSP, NPU, audio, and other peripherals
// ============================================================================


// ============================================================================
// TIER 0: SYSTEM MEMORY
// ============================================================================

// ----------------------------------------------------------------------------
// 0. BOOT ROM
// ----------------------------------------------------------------------------
// Firmware boot image storage.
//
// Base address : 0x0000_0000
// Size         : 4 KB
// ----------------------------------------------------------------------------

`define ROM_BASE_ADDR       32'h0000_0000
`define ROM_SIZE            32'h0000_1000
`define ROM_END_ADDR        (`ROM_BASE_ADDR + `ROM_SIZE)


// ----------------------------------------------------------------------------
// 1. SYSTEM RAM
// ----------------------------------------------------------------------------
// Main system memory used by the CPU after the boot process.
//
// Base address : 0x1000_0000
// Size         : 64 KB
// ----------------------------------------------------------------------------

`define RAM_BASE_ADDR       32'h1000_0000
`define RAM_SIZE            32'h0001_0000
`define RAM_END_ADDR        (`RAM_BASE_ADDR + `RAM_SIZE)


// ============================================================================
// TIER 1: SYSTEM CORE PERIPHERALS
// ============================================================================

// ----------------------------------------------------------------------------
// 2. HARDWARE TIMER
// ----------------------------------------------------------------------------
//
// Base address : 0x4000_0000
//
// Register map:
//   +0x00 : Control register
//   +0x04 : Compare value
//   +0x08 : Counter value
//   +0x0C : Interrupt status
//
// CTRL register:
//   Bit 0 : Timer enable
//   Bit 1 : Auto reload
//   Bit 2 : Interrupt enable
//
// STATUS register:
//   Bit 0 : Interrupt pending
//           W1C (Write 1 to Clear)
// ----------------------------------------------------------------------------

`define TIMER_BASE_ADDR     32'h4000_0000

`define TIMER_CTRL          32'h0000_0000
`define TIMER_COMPARE       32'h0000_0004
`define TIMER_COUNTER       32'h0000_0008
`define TIMER_STATUS        32'h0000_000C

`define TIMER_SIZE          32'h0000_0100
`define TIMER_END_ADDR      (`TIMER_BASE_ADDR + `TIMER_SIZE)


// ----------------------------------------------------------------------------
// 3. INTERRUPT ARBITER
// ----------------------------------------------------------------------------
//
// Base address : 0x4000_1000
//
// Register map:
//   +0x00 : Pending interrupt register
//   +0x04 : Interrupt enable register
//   +0x08 : Interrupt clear register
//
// PENDING:
//   Read-only interrupt pending status.
//
// ENABLE:
//   Bit = 1 : Interrupt source enabled.
//   Bit = 0 : Interrupt source disabled.
//
// CLEAR:
//   W1C (Write 1 to Clear).
// ----------------------------------------------------------------------------

`define IRQ_BASE_ADDR       32'h4000_1000

`define IRQ_REG_PENDING     32'h0000_0000
`define IRQ_REG_ENABLE      32'h0000_0004
`define IRQ_REG_CLEAR       32'h0000_0008

`define IRQ_SIZE            32'h0000_0100
`define IRQ_END_ADDR        (`IRQ_BASE_ADDR + `IRQ_SIZE)


// ============================================================================
// TIER 2: APPLICATION ACCELERATORS
// ----------------------------------------------------------------------------
// Reserved address space for application-specific peripherals.
//
// Future examples:
//   - DSP accelerators
//   - Audio processing modules
//   - NPU / AI accelerators
//   - Custom hardware peripherals
//
// New accelerator definitions should be added below without modifying the
// Tier 0 or Tier 1 memory map.
// ============================================================================


// ----------------------------------------------------------------------------
// DSP ACCELERATOR TEMPLATE
// ----------------------------------------------------------------------------
//
// Example placeholder for a future memory-mapped DSP peripheral.
//
// `define DSP_BASE_ADDR       32'h8000_0000
// `define DSP_SIZE            32'h0000_0100
// `define DSP_END_ADDR        (`DSP_BASE_ADDR + `DSP_SIZE)
//
// Register definitions can be added when a specific DSP peripheral is
// integrated into the SoC.
// ----------------------------------------------------------------------------


// ============================================================================
// END OF MEMORY MAP
// ============================================================================

`endif
