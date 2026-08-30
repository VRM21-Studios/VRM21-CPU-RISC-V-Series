`ifndef VRM_SOC_MAP_RV64_VH
`define VRM_SOC_MAP_RV64_VH

// ============================================================================
// Memory Map    : RV64 System Architecture
// Description   : Memory-mapped address definitions for the VRM RV64IMFD
//                 processor SoC.
//
// Address Space:
//   Tier 0 : System core peripherals integrated within the CPU wrapper.
//   Tier 1 : Main data memory accessed through the external memory interface.
//   Tier 2 : Application accelerators and audio/DSP peripherals accessed
//            through the external memory interface.
//
// Notes:
// - All addresses are defined as 64-bit values.
// - Address ranges use an inclusive lower bound and an exclusive upper bound.
// - Peripheral and memory addresses are intended to be used by the SoC
//   address-decoding logic.
// ============================================================================

// ============================================================================
// TIER 0: SYSTEM CORE PERIPHERALS
// ============================================================================
// Peripherals integrated directly into the RV64 CPU wrapper.

// -----------------------------------------------------------------------------
// Hardware Timer
// -----------------------------------------------------------------------------

`define TIMER_BASE_ADDR       64'h0000_0000_0000_0000
`define TIMER_END_ADDR        64'h0000_0000_0000_0100

// -----------------------------------------------------------------------------
// Interrupt Arbiter
// -----------------------------------------------------------------------------

`define IRQ_BASE_ADDR         64'h0000_0000_0000_1000
`define IRQ_END_ADDR          64'h0000_0000_0000_1100

// ============================================================================
// TIER 1: MAIN DATA MEMORY
// ============================================================================
// Main data memory accessed through the external memory interface.

`define DMEM_BASE_ADDR        64'h0000_0000_0000_4000
`define DMEM_END_ADDR         64'h0000_0000_0000_8000

// ============================================================================
// TIER 2: APPLICATION ACCELERATORS / AUDIO DSP
// ============================================================================
// Reserved address space for future application-specific accelerators and
// audio/DSP peripherals.
//
// The following region is currently defined as an example/reserved mapping
// for future hardware accelerator integration.

// -----------------------------------------------------------------------------
// Example Accelerator Region
// -----------------------------------------------------------------------------
// Reserved 4 KB address space for a future AXI-connected accelerator.
// This mapping does not imply that the corresponding accelerator is currently
// included in this repository release.

`define OSC_AXI_BASE_ADDR     64'h0000_0000_4000_0000
`define OSC_AXI_END_ADDR      64'h0000_0000_4000_1000

`endif
