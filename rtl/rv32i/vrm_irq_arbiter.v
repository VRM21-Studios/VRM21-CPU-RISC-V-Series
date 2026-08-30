`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_irq_arbiter
// Description : Interrupt request arbiter and controller with MMIO
//               configuration interface.
//
// Features:
// - Supports up to 32 independent interrupt sources.
// - Detects rising edges on interrupt source inputs.
// - Maintains pending interrupt status.
// - Provides per-source interrupt enable control.
// - Supports Write-1-to-Clear (W1C) for pending interrupts.
// - Generates a single interrupt request toward the CPU when an enabled
//   interrupt is pending.
// - Provides a simple synchronous MMIO write interface and combinational
//   MMIO read interface.
//
// Interrupt Source Mapping:
// - irq_src[0]     : Timer interrupt source.
// - irq_src[31:1]  : External or future interrupt sources.
//
// MMIO Register Map:
// - 0x00 : Pending Register
//          Read-only status of pending interrupt sources.
// - 0x04 : Enable Register
//          Read/write interrupt enable bits.
// - 0x08 : Pending Clear Register
//          Write-1-to-Clear pending interrupt bits.
//
// Interrupt Detection:
// - Each irq_src bit is monitored for a rising edge (0 -> 1).
// - A detected rising edge sets the corresponding pending bit.
// - Pending status remains asserted until explicitly cleared through the
//   W1C register.
//
// CPU Interrupt Generation:
// - cpu_irq_trigger is asserted when at least one interrupt source is both
//   pending and enabled:
//
//       cpu_irq_trigger = |(pending & enable)
//
// Notes:
// - irq_src_d1 stores the previous-cycle interrupt source state.
// - Interrupt source inputs are therefore sampled synchronously to clk.
// - The design is intended to be synthesis-friendly for FPGA implementation.
// ============================================================================

module vrm_irq_arbiter (
    input  wire clk,
    input  wire rstn,

    // =========================================================================
    // MMIO INTERFACE
    // =========================================================================
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // =========================================================================
    // INTERRUPT SOURCES
    // =========================================================================
    // Bit 0  : Timer
    // Bit 1-31 : External / Future interrupt sources
    input  wire [31:0] irq_src,

    // =========================================================================
    // CPU INTERRUPT OUTPUT
    // =========================================================================
    output wire        cpu_irq_trigger
);

    // =========================================================================
    // INTERRUPT CONTROL REGISTERS
    // =========================================================================
    // pending : Latched interrupt requests waiting to be serviced/cleared.
    // enable  : Per-source interrupt enable mask.
    //
    // irq_src_d1 stores the previous sampled state of irq_src and is used
    // for rising-edge detection.
    reg [31:0] pending;
    reg [31:0] enable;
    reg [31:0] irq_src_d1;

    // =========================================================================
    // RISING-EDGE DETECTION
    // =========================================================================
    // Detect a 0 -> 1 transition on each interrupt source independently.
    //
    // Current source = 1
    // Previous source = 0
    // Result           = 1
    //
    // The bitwise implementation keeps the logic simple and synthesis-friendly.
    wire [31:0] irq_rising_edge = irq_src & ~irq_src_d1;

    // =========================================================================
    // INTERRUPT STATE UPDATE
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            pending    <= 32'h0;
            enable     <= 32'h0;
            irq_src_d1 <= 32'h0;
        end else begin

            // Store the current interrupt source state for use during
            // rising-edge detection on the next clock cycle.
            irq_src_d1 <= irq_src;

            // -----------------------------------------------------------------
            // MMIO WRITE HANDLING
            // -----------------------------------------------------------------
            if (we) begin
                case (addr[7:0])

                    // ---------------------------------------------------------
                    // 0x04 : ENABLE REGISTER
                    // ---------------------------------------------------------
                    // Directly update the interrupt enable mask.
                    8'h04: begin
                        enable <= wdata;
                    end

                    // ---------------------------------------------------------
                    // 0x08 : PENDING CLEAR REGISTER
                    // ---------------------------------------------------------
                    // Write-1-to-Clear (W1C):
                    // - Writing 1 clears the corresponding pending bit.
                    // - Writing 0 leaves the pending bit unchanged.
                    //
                    // A newly detected interrupt is still captured through
                    // irq_rising_edge in the same update expression.
                    8'h08: begin
                        pending <= (pending | irq_rising_edge) & ~wdata;
                    end

                    // ---------------------------------------------------------
                    // OTHER ADDRESSES
                    // ---------------------------------------------------------
                    // No control register is modified. New interrupt edges
                    // are still captured into the pending register.
                    default: begin
                        pending <= pending | irq_rising_edge;
                    end

                endcase
            end else begin

                // No MMIO write:
                // latch any newly detected interrupt request.
                pending <= pending | irq_rising_edge;

            end
        end
    end

    // =========================================================================
    // MMIO READ LOGIC
    // =========================================================================
    // Read access is combinational. Only defined register addresses return
    // meaningful data.
    always @(*) begin
        case (addr[7:0])

            // 0x00 : Pending interrupt status
            8'h00: rdata = pending;

            // 0x04 : Interrupt enable mask
            8'h04: rdata = enable;

            // Undefined addresses return zero.
            default: rdata = 32'h0;

        endcase
    end

    // =========================================================================
    // CPU INTERRUPT REQUEST GENERATION
    // =========================================================================
    // Assert the CPU interrupt request whenever at least one interrupt source
    // is simultaneously pending and enabled.
    assign cpu_irq_trigger = |(pending & enable);

endmodule
