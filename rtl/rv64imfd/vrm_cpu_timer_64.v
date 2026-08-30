`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_cpu_timer_64
// Description : 64-bit memory-mapped hardware timer for the VRM RISC-V
//               processor core.
//
// Register Map:
//   0x00 : CTRL    - Timer control register
//   0x04 : COMPARE - Timer compare value
//   0x08 : COUNTER - Current timer counter value
//   0x0C : STATUS  - Timer status register
//
// Control Register:
//   CTRL[0] : Timer enable
//   CTRL[1] : Counter auto-reset enable
//   CTRL[2] : Timer interrupt enable
//
// Status Register:
//   STATUS[0] : Timer compare event / interrupt status
//
// Interface:
// - 64-bit MMIO address and data bus.
// - Internal timer registers remain 32-bit.
// - Read data is zero-extended to 64 bits.
// - Write operations use the lower 32 bits of wdata.
// - irq_out is asserted when the timer interrupt is enabled and the
//   compare-event status bit is set.
//
// Notes:
// - The timer counter increments once per clock cycle while enabled.
// - When counter reaches or exceeds compare, STATUS[0] is asserted.
// - If CTRL[1] is enabled, the counter is reset to zero after the compare
//   event.
// - STATUS[0] can be cleared by writing a '1' to the corresponding bit.
// ============================================================================

module vrm_cpu_timer_64 (
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
    // TIMER INTERRUPT OUTPUT
    // =========================================================================

    output wire        irq_out
);

    // =========================================================================
    // INTERNAL TIMER REGISTERS
    // =========================================================================
    // Timer state is maintained using 32-bit registers. Values are
    // zero-extended when presented to the 64-bit CPU bus.

    reg [31:0] ctrl;
    reg [31:0] compare;
    reg [31:0] counter;
    reg [31:0] status;

    // =========================================================================
    // INTERRUPT GENERATION
    // =========================================================================
    // The timer interrupt is asserted only when both the interrupt-enable
    // control bit and the timer status bit are set.

    assign irq_out = ctrl[2] & status[0];

    // =========================================================================
    // TIMER CONTROL AND COUNTER
    // =========================================================================

    always @(posedge clk) begin

        if (!rstn) begin

            ctrl    <= 32'h0;
            compare <= 32'hFFFFFFFF;
            counter <= 32'h0;
            status  <= 32'h0;

        end else begin

            // -----------------------------------------------------------------
            // MMIO WRITE ACCESS
            // -----------------------------------------------------------------
            // Only the lower 32 bits of the 64-bit write data are stored.

            if (we) begin

                case (addr[7:0])

                    // ---------------------------------------------------------
                    // CTRL
                    // ---------------------------------------------------------
                    8'h00:
                        ctrl <= wdata[31:0];

                    // ---------------------------------------------------------
                    // COMPARE
                    // ---------------------------------------------------------
                    8'h04:
                        compare <= wdata[31:0];

                    // ---------------------------------------------------------
                    // COUNTER
                    // ---------------------------------------------------------
                    8'h08:
                        counter <= wdata[31:0];

                    // ---------------------------------------------------------
                    // STATUS
                    // ---------------------------------------------------------
                    // Write-one-to-clear behavior for status bits.
                    8'h0C:
                        status <= status & ~wdata[31:0];

                endcase

            end

            // -----------------------------------------------------------------
            // TIMER OPERATION
            // -----------------------------------------------------------------
            // The counter advances only while the timer is enabled.

            if (ctrl[0]) begin

                // -------------------------------------------------------------
                // COMPARE EVENT
                // -------------------------------------------------------------

                if (counter >= compare) begin

                    status[0] <= 1'b1;

                    // ---------------------------------------------------------
                    // OPTIONAL COUNTER AUTO-RESET
                    // ---------------------------------------------------------

                    if (ctrl[1])
                        counter <= 32'h0;

                end else begin

                    // ---------------------------------------------------------
                    // COUNTER INCREMENT
                    // ---------------------------------------------------------

                    counter <= counter + 1;

                end
            end
        end
    end

    // =========================================================================
    // MMIO READ DATA
    // =========================================================================
    // Internal 32-bit registers are zero-extended to the 64-bit bus width.

    always @(*) begin

        case (addr[7:0])

            // -----------------------------------------------------------------
            // CTRL
            // -----------------------------------------------------------------
            8'h00:
                rdata = {32'b0, ctrl};

            // -----------------------------------------------------------------
            // COMPARE
            // -----------------------------------------------------------------
            8'h04:
                rdata = {32'b0, compare};

            // -----------------------------------------------------------------
            // COUNTER
            // -----------------------------------------------------------------
            8'h08:
                rdata = {32'b0, counter};

            // -----------------------------------------------------------------
            // STATUS
            // -----------------------------------------------------------------
            8'h0C:
                rdata = {32'b0, status};

            // -----------------------------------------------------------------
            // DEFAULT
            // -----------------------------------------------------------------
            // Unmapped addresses return zero.

            default:
                rdata = 64'h0;

        endcase
    end

endmodule
