`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_timer
// DESCRIPTION : 32-bit memory-mapped compare timer that drives the machine
//               timer interrupt (MTIP) of the RV32IM core.
//
// Registers (word offsets inside the timer window, see vrm_soc_map_rv32i.vh):
//   0x00 CTRL     [0] enable, [1] auto-reload to 0, [2] interrupt enable
//   0x04 COMPARE  match value (reset value 0xFFFF_FFFF)
//   0x08 COUNTER  running count, writable
//   0x0C STATUS   [0] interrupt pending, write 1 to clear (W1C)
//
// Interrupt Behavior:
//   irq_out = CTRL[2] & STATUS[0]. STATUS[0] is set when COUNTER >= COMPARE.
//   With auto-reload the period is COMPARE + 1 clock cycles.
//
// Notes:
//   - This is not the RISC-V mtime/mtimecmp pair; it is a 32-bit local timer.
//     The FreeRTOS port uses it through the no-MTIME extension.
//   - While the timer is enabled, the count update in the same cycle takes
//     priority over a software write to COUNTER.
// ============================================================================
module vrm_timer (
    input  wire clk,
    input  wire rstn,

    // Bus interface (MMIO)
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // Interrupt output to the core
    output wire        irq_out
);

    reg [31:0] ctrl;    // [0]=EN, [1]=AUTO_RELOAD, [2]=IRQ_EN
    reg [31:0] compare;
    reg [31:0] counter;
    reg [31:0] status;  // [0]=IRQ pending

    assign irq_out = ctrl[2] & status[0];

    always @(posedge clk) begin
        if (!rstn) begin
            ctrl    <= 32'h0;
            compare <= 32'hFFFFFFFF;
            counter <= 32'h0;
            status  <= 32'h0;
        end else begin
            // Register writes from the core
            if (we) begin
                case (addr[7:0])
                    8'h00: ctrl    <= wdata;
                    8'h04: compare <= wdata;
                    8'h08: counter <= wdata;
                    8'h0C: status  <= status & ~wdata; // W1C
                endcase
            end

            // Count and compare
            if (ctrl[0]) begin
                if (counter >= compare) begin
                    status[0] <= 1'b1;
                    if (ctrl[1]) counter <= 32'h0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

    // Combinational read
    always @(*) begin
        case (addr[7:0])
            8'h00: rdata = ctrl;
            8'h04: rdata = compare;
            8'h08: rdata = counter;
            8'h0C: rdata = status;
            default: rdata = 32'h0;
        endcase
    end

endmodule
