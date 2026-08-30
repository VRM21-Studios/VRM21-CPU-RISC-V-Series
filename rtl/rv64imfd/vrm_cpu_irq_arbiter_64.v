`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_cpu_irq_arbiter_64
// Description : 64-bit memory-mapped interrupt arbiter for the VRM RISC-V
//               processor core.
//
// Register Map:
//   0x00 : PENDING - Pending interrupt status
//   0x04 : ENABLE  - Interrupt enable mask
//   0x08 : PENDING - Pending interrupt clear register
//
// Interface:
// - 64-bit MMIO address and data bus.
// - Interrupt sources are provided through a 32-bit irq_src input.
// - Rising edges on interrupt sources are detected and latched into
//   the pending register.
// - Interrupt sources can be individually enabled through the enable mask.
// - cpu_irq_trigger is asserted when at least one enabled interrupt is pending.
//
// Notes:
// - Internal interrupt registers remain 32-bit.
// - MMIO read data is zero-extended to 64 bits.
// - MMIO writes use the lower 32 bits of wdata.
// - Interrupt pending bits are generated from rising edges of irq_src.
// - Writing to the pending register clears the corresponding pending bits.
// ============================================================================

module vrm_cpu_irq_arbiter_64 (
    input  wire        clk,
    input  wire        rstn,

    // =========================================================================
    // 64-BIT MEMORY-MAPPED INTERFACE
    // =========================================================================

    input  wire [63:0] addr,
    input  wire [63:0] wdata,
    input  wire        we,
    output reg  [63:0] rdata,

    // =========================================================================
    // INTERRUPT SOURCE INTERFACE
    // =========================================================================

    input  wire [31:0] irq_src,
    output wire        cpu_irq_trigger
);

    // =========================================================================
    // INTERNAL INTERRUPT REGISTERS
    // =========================================================================

    reg [31:0] pending;
    reg [31:0] enable;
    reg [31:0] irq_src_d1;

    // =========================================================================
    // INTERRUPT RISING-EDGE DETECTION
    // =========================================================================
    // Detect rising edges by comparing the current interrupt source state
    // against its value sampled during the previous clock cycle.

    wire [31:0] irq_rising_edge = irq_src & ~irq_src_d1;

    // =========================================================================
    // INTERRUPT STATE MANAGEMENT
    // =========================================================================

    always @(posedge clk) begin

        if (!rstn) begin

            pending    <= 32'h0;
            enable     <= 32'h0;
            irq_src_d1 <= 32'h0;

        end else begin

            // -----------------------------------------------------------------
            // SAMPLE INTERRUPT SOURCES
            // -----------------------------------------------------------------

            irq_src_d1 <= irq_src;

            // -----------------------------------------------------------------
            // MMIO WRITE ACCESS
            // -----------------------------------------------------------------

            if (we) begin

                case (addr[7:0])

                    // ---------------------------------------------------------
                    // ENABLE REGISTER
                    // ---------------------------------------------------------
                    8'h04:
                        enable <= wdata[31:0];

                    // ---------------------------------------------------------
                    // PENDING REGISTER
                    // ---------------------------------------------------------
                    // Clear selected pending bits while preserving newly
                    // detected interrupt events.

                    8'h08:
                        pending <= (pending | irq_rising_edge) & ~wdata[31:0];

                    // ---------------------------------------------------------
                    // DEFAULT
                    // ---------------------------------------------------------
                    // Preserve existing pending interrupts and latch any
                    // newly detected rising-edge events.

                    default:
                        pending <= pending | irq_rising_edge;

                endcase

            end else begin

                // -----------------------------------------------------------------
                // LATCH NEW INTERRUPT EVENTS
                // -----------------------------------------------------------------

                pending <= pending | irq_rising_edge;

            end
        end
    end

    // =========================================================================
    // MMIO READ DATA
    // =========================================================================
    // Internal 32-bit interrupt registers are zero-extended to the 64-bit
    // processor bus width.

    always @(*) begin

        case (addr[7:0])

            // -----------------------------------------------------------------
            // PENDING REGISTER
            // -----------------------------------------------------------------
            8'h00:
                rdata = {32'b0, pending};

            // -----------------------------------------------------------------
            // ENABLE REGISTER
            // -----------------------------------------------------------------
            8'h04:
                rdata = {32'b0, enable};

            // -----------------------------------------------------------------
            // DEFAULT
            // -----------------------------------------------------------------
            // Unmapped addresses return zero.

            default:
                rdata = 64'h0;

        endcase
    end

    // =========================================================================
    // CPU INTERRUPT TRIGGER
    // =========================================================================
    // Asserted whenever at least one pending interrupt is enabled.

    assign cpu_irq_trigger = |(pending & enable);

endmodule
