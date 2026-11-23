`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_irq_arbiter
// DESCRIPTION : Edge-triggered interrupt aggregator. Latches rising edges of
//               32 sources into PENDING and raises one line to the core when
//               any pending source is enabled.
//
// Registers (word offsets inside the arbiter window, see vrm_soc_map_rv32i.vh):
//   0x00 PENDING  read-only view of latched rising edges
//   0x04 ENABLE   per-source enable mask
//   0x08 CLEAR    write 1 to clear the matching PENDING bits (W1C)
//
// Notes:
//   - Bit 0 is the hardware timer, bits 1..31 are external sources.
//   - A rising edge that arrives in the same cycle as a CLEAR write is kept
//     unless the CLEAR write names the same bit.
// ============================================================================
module vrm_irq_arbiter (
    input  wire clk,
    input  wire rstn,

    // Bus interface (MMIO)
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // Interrupt sources (bit 0: timer, bits 1..31: external)
    input  wire [31:0] irq_src,

    // To CPU
    output wire        cpu_irq_trigger
);

    reg [31:0] pending;
    reg [31:0] enable;
    reg [31:0] irq_src_d1; // previous source levels for edge detection

    wire [31:0] irq_rising_edge = irq_src & ~irq_src_d1;

    always @(posedge clk) begin
        if (!rstn) begin
            pending    <= 32'h0;
            enable     <= 32'h0;
            irq_src_d1 <= 32'h0;
        end else begin
            irq_src_d1 <= irq_src;

            if (we) begin
                case (addr[7:0])
                    8'h04: enable <= wdata;
                    8'h08: pending <= (pending | irq_rising_edge) & ~wdata; // W1C
                    default: pending <= pending | irq_rising_edge;
                endcase
            end else begin
                pending <= pending | irq_rising_edge;
            end
        end
    end

    always @(*) begin
        case (addr[7:0])
            8'h00: rdata = pending;
            8'h04: rdata = enable;
            default: rdata = 32'h0;
        endcase
    end

    assign cpu_irq_trigger = |(pending & enable);

endmodule
