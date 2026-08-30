`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_timer
// Description : Programmable 32-bit timer with MMIO configuration interface
//               and interrupt generation.
//
// Features:
// - 32-bit programmable counter.
// - Programmable compare value.
// - Timer enable control.
// - Optional automatic counter reload.
// - Interrupt enable control.
// - Latched interrupt pending status.
// - Write-1-to-Clear (W1C) interrupt status.
// - Software-accessible counter for manual initialization or reset.
// - Simple MMIO register interface.
//
// Control Register:
// - ctrl[0] : Timer Enable
// - ctrl[1] : Auto Reload Enable
// - ctrl[2] : Interrupt Enable
//
// Interrupt Behavior:
// - When the timer counter reaches or exceeds the compare value, the
//   interrupt pending flag is asserted.
// - irq_out is asserted when both Interrupt Enable and Interrupt Pending
//   are set:
//
//       irq_out = ctrl[2] & status[0]
//
// - When Auto Reload is enabled, the counter is cleared to zero after
//   reaching the compare value.
// - When Auto Reload is disabled, the counter remains at the compare value
//   and the pending flag remains asserted until cleared by software.
//
// MMIO Register Map:
// - 0x00 : Control Register
// - 0x04 : Compare Register
// - 0x08 : Counter Register
// - 0x0C : Status Register
//
// Notes:
// - Register writes and timer operation are synchronous to clk.
// - MMIO read data is provided combinationally.
// - Status bit 0 uses Write-1-to-Clear semantics.
// ============================================================================

module vrm_timer (
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
    // INTERRUPT OUTPUT
    // =========================================================================
    output wire        irq_out
);

    // =========================================================================
    // TIMER REGISTERS
    // =========================================================================
    // ctrl:
    //   [0] : Timer Enable
    //   [1] : Auto Reload Enable
    //   [2] : Interrupt Enable
    //
    // compare:
    //   Counter threshold that triggers the timer event.
    //
    // counter:
    //   Current timer count.
    //
    // status:
    //   [0] : Interrupt Pending
    reg [31:0] ctrl;
    reg [31:0] compare;
    reg [31:0] counter;
    reg [31:0] status;

    // =========================================================================
    // INTERRUPT GENERATION
    // =========================================================================
    // The timer interrupt is active only when the interrupt is both enabled
    // and pending.
    assign irq_out = ctrl[2] & status[0];

    // =========================================================================
    // SYNCHRONOUS TIMER CONTROL AND COUNTING
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            ctrl    <= 32'h0;
            compare <= 32'hFFFFFFFF;
            counter <= 32'h0;
            status  <= 32'h0;
        end else begin

            // -----------------------------------------------------------------
            // MMIO WRITE HANDLING
            // -----------------------------------------------------------------
            if (we) begin
                case (addr[7:0])

                    // 0x00 : Control Register
                    8'h00: ctrl <= wdata;

                    // 0x04 : Compare Register
                    8'h04: compare <= wdata;

                    // 0x08 : Counter Register
                    // Software can directly initialize or reset the counter.
                    8'h08: counter <= wdata;

                    // 0x0C : Status Register
                    // Write-1-to-Clear:
                    // Writing a 1 to a status bit clears that bit.
                    8'h0C: status <= status & ~wdata;

                endcase
            end

            // -----------------------------------------------------------------
            // TIMER COUNTER OPERATION
            // -----------------------------------------------------------------
            if (ctrl[0]) begin

                // Timer event occurs when the counter reaches or exceeds
                // the configured compare value.
                if (counter >= compare) begin

                    // Latch the timer interrupt request.
                    status[0] <= 1'b1;

                    // Reload the counter when automatic reload is enabled.
                    if (ctrl[1])
                        counter <= 32'h0;

                end else begin

                    // Continue counting toward the compare value.
                    counter <= counter + 1;

                end
            end
        end
    end

    // =========================================================================
    // MMIO READ LOGIC
    // =========================================================================
    // Read data is selected combinationally based on the MMIO address.
    always @(*) begin
        case (addr[7:0])

            // 0x00 : Control Register
            8'h00: rdata = ctrl;

            // 0x04 : Compare Register
            8'h04: rdata = compare;

            // 0x08 : Current Counter Value
            8'h08: rdata = counter;

            // 0x0C : Timer Status
            8'h0C: rdata = status;

            // Undefined addresses return zero.
            default: rdata = 32'h0;

        endcase
    end

endmodule
