`ifndef VRM_SOC_MAP_RV32I_VH
`define VRM_SOC_MAP_RV32I_VH

// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// FILE        : vrm_soc_map_rv32i.vh
// DESCRIPTION : CPU-side memory map of the RV32IM + VCF + FreeRTOS SoC.
//               Must stay consistent with gcc-firmware/rv32im_freertos/soc_map.h
//               and with the host-side register offsets.
//
// Notes:
//   - The file name keeps the rv32i suffix because the RTL includes it by
//     this name.
// ============================================================================

// ----------------------------------------------------------------------------
// TIER 0: SYSTEM MEMORY (boot and data storage)
// ----------------------------------------------------------------------------
`define ROM_BASE_ADDR       32'h0000_0000
`define ROM_SIZE            32'h0000_1000
`define ROM_END_ADDR        (`ROM_BASE_ADDR + `ROM_SIZE)

`define RAM_BASE_ADDR       32'h1000_0000
`define RAM_SIZE            32'h0001_0000
`define RAM_END_ADDR        (`RAM_BASE_ADDR + `RAM_SIZE)

// ----------------------------------------------------------------------------
// TIER 1: SYSTEM CORE PERIPHERALS (timer and interrupts)
// ----------------------------------------------------------------------------
`define TIMER_BASE_ADDR     32'h4000_0000
`define TIMER_CTRL          32'h0000_0000
`define TIMER_COMPARE       32'h0000_0004
`define TIMER_COUNTER       32'h0000_0008
`define TIMER_STATUS        32'h0000_000C
`define TIMER_SIZE          32'h0000_0100
`define TIMER_END_ADDR      (`TIMER_BASE_ADDR + `TIMER_SIZE)

`define IRQ_BASE_ADDR       32'h4000_1000
`define IRQ_REG_PENDING     32'h0000_0000
`define IRQ_REG_ENABLE      32'h0000_0004
`define IRQ_REG_CLEAR       32'h0000_0008
`define IRQ_SIZE            32'h0000_0100
`define IRQ_END_ADDR        (`IRQ_BASE_ADDR + `IRQ_SIZE)

// ----------------------------------------------------------------------------
// TIER 2: APPLICATION ACCELERATORS - Wavetable Oscillator (reserved)
// ----------------------------------------------------------------------------
// NOTE: No oscillator is instantiated in this SoC and vrm_soc_top does not
// decode this range. The window and offsets are reserved so that the range
// is never reassigned to another block.
`define OSC_BASE_ADDR       32'h8000_1000
`define OSC_SIZE            32'h0000_0100
`define OSC_END_ADDR        (`OSC_BASE_ADDR + `OSC_SIZE)

// Register offsets (4-bit, word-aligned)
`define OSC_REG_CTRL        4'h0   // [0] enable, [1] force_swap (bypass ZCD)
`define OSC_REG_PHASE_INC   4'h1   // phase increment (32-bit)
`define OSC_REG_AMPLITUDE   4'h2   // amplitude (fractional)
`define OSC_REG_SWAP_REQ    4'h3   // [0] swap request (self-clearing)
`define OSC_REG_STATUS      4'h4   // [0] active_bank, [1] swap_pending,
                                    // [2] zcd_event, [3] wt_stream_active

// ----------------------------------------------------------------------------
// TIER 2: APPLICATION ACCELERATORS - VCF (Chamberlin SVF, stereo)
// ----------------------------------------------------------------------------
//   CTRL   W : [0] enable (0 = zero-latency bypass)
//              [2] commit arm (L+R)        -> write 5 = enable + LP + commit
//              [4:3] ftype shadow (0=LP, 1=HP, 2=BP)
//          R : reg_ctrl | {commit_status, 31'b0}
//   CUTOFF   : Q1.15 shadow
//   RES      : Q1.15 shadow
//   LCO      : unsigned shadow
// Commit protocol: every register write cancels a pending commit; a CTRL
// write with bit 2 = 1 arms it. The last write of an update must therefore be
// CTRL with bit 2 = 1. The commit is applied at the first zero crossing after
// the arm (or after the ZCD timeout).
// Decode uses sb_addr[5:2]: byte offsets 0x10-0x3C read 0 / ignore writes;
// 0x40-0xFF alias onto 0x00-0x3C.
`define VCF_BASE_ADDR       32'h8000_2000
`define VCF_SIZE            32'h0000_0100
`define VCF_END_ADDR        (`VCF_BASE_ADDR + `VCF_SIZE)

// Register offsets (4-bit word index = byte offset >> 2)
`define VCF_REG_CTRL        4'h0   // byte offset 0x00
`define VCF_REG_CUTOFF      4'h1   // byte offset 0x04
`define VCF_REG_RES         4'h2   // byte offset 0x08
`define VCF_REG_LCO         4'h3   // byte offset 0x0C

// CTRL field positions
`define VCF_CTRL_BIT_ENABLE 0
`define VCF_CTRL_BIT_COMMIT 2
`define VCF_CTRL_FTYPE_LSB  3
`define VCF_CTRL_BIT_STATUS 31     // read-only: commit armed (L | R)

`endif
