`timescale 1ns / 1ps
`include "vrm_soc_map_rv64.vh"

// ============================================================================
// Module      : vrm_cpu_rv64_wrapper
// Description : Memory-mapped SoC wrapper for the VRM RV64IMFD processor.
//
// Responsibilities:
// - Connects the RV64IMFD CPU core to instruction and external data memory.
// - Integrates the hardware timer.
// - Integrates the interrupt arbiter.
// - Synchronizes external interrupt sources using a two-stage flip-flop chain.
// - Routes local MMIO accesses to the corresponding peripheral.
// - Routes non-local memory accesses to the external memory interface.
// - Provides 8-bit byte write strobes for external memory transactions.
//
// Local Peripherals:
// - Hardware Timer
// - Interrupt Arbiter
//
// Interrupt Sources:
// - irq_sources[0]    : Internal hardware timer interrupt.
// - irq_sources[31:1] : Synchronized external interrupt sources.
//
// Notes:
// - Local peripheral accesses do not propagate the external memory busy signal
//   to the CPU core.
// - External memory write strobes are disabled during local peripheral access.
// - Peripheral writes are enabled when the CPU write-enable signal and the
//   corresponding address decode are active, with byte strobe bit 0 asserted.
// - External interrupt inputs are synchronized using two sequential stages
//   before being passed to the interrupt arbiter.
// ============================================================================

module vrm_cpu_rv64_wrapper(
    input  wire clk,
    input  wire rstn,

    // =========================================================================
    // INSTRUCTION MEMORY INTERFACE
    // =========================================================================

    output wire [63:0] pc_out,
    input  wire [31:0] instr_in,

    // =========================================================================
    // EXTERNAL DATA MEMORY INTERFACE
    // =========================================================================
    // The 8-bit write strobe provides byte-level write enables for the
    // 64-bit external data memory interface.

    output wire [63:0] ext_mem_addr,
    output wire [63:0] ext_mem_wdata,
    output wire [7:0]  ext_mem_wstrb,
    output wire        ext_mem_we,
    input  wire [63:0] ext_mem_rdata,
    input  wire        ext_mem_busy,

    // =========================================================================
    // EXTERNAL INTERRUPT SOURCES
    // =========================================================================
    // 31 external interrupt inputs are provided. Interrupt source bit 0 of
    // the internal arbiter is reserved for the hardware timer.

    input  wire [30:0] ext_irq_in,

    // =========================================================================
    // DEBUG AND CPU STATUS
    // =========================================================================

    output wire [63:0] debug_reg_x1,
    output wire        cpu_halt
);

    // =========================================================================
    // INTERNAL INTERCONNECT SIGNALS
    // =========================================================================

    wire        irq_to_cpu;
    wire        timer_irq;

    wire [63:0] cpu_mem_addr;
    wire [63:0] cpu_mem_wdata;
    wire [7:0]  cpu_mem_wstrb;
    wire        cpu_mem_we;
    reg  [63:0] cpu_mem_rdata;

    wire [63:0] timer_rdata;
    wire [63:0] arbiter_rdata;

    // =========================================================================
    // LOCAL ADDRESS DECODING
    // =========================================================================
    // Decode CPU memory accesses to determine whether the transaction targets
    // a local memory-mapped peripheral or external memory.

    wire timer_sel   = (cpu_mem_addr >= `TIMER_BASE_ADDR) && (cpu_mem_addr < `TIMER_END_ADDR);
    wire arbiter_sel = (cpu_mem_addr >= `IRQ_BASE_ADDR)   && (cpu_mem_addr < `IRQ_END_ADDR);
    wire local_access = timer_sel | arbiter_sel;

    // =========================================================================
    // CPU MEMORY BUSY CONTROL
    // =========================================================================
    // Local peripheral accesses are always considered immediately available.
    // Only external memory transactions propagate the external busy signal.

    wire mem_busy_core = local_access ? 1'b0 : ext_mem_busy;

    // =========================================================================
    // EXTERNAL INTERRUPT SYNCHRONIZATION
    // =========================================================================
    // Synchronize external interrupt inputs using a two-stage flip-flop chain
    // to reduce the risk of metastability when crossing into the CPU clock
    // domain.

    reg [30:0] ext_irq_sync1, ext_irq_sync2;

    always @(posedge clk or negedge rstn) begin

        if (!rstn) begin

            ext_irq_sync1 <= 31'b0;
            ext_irq_sync2 <= 31'b0;

        end else begin

            ext_irq_sync1 <= ext_irq_in;
            ext_irq_sync2 <= ext_irq_sync1;

        end
    end

    // =========================================================================
    // RV64IMFD CPU CORE
    // =========================================================================

    vrm_cpu_rv64_core core (
        .clk          (clk),
        .rstn         (rstn),
        .irq          (irq_to_cpu),
        .pc_out       (pc_out),
        .instr_in     (instr_in),
        .mem_addr     (cpu_mem_addr),
        .mem_wdata    (cpu_mem_wdata),
        .mem_wstrb    (cpu_mem_wstrb),
        .mem_we       (cpu_mem_we),
        .mem_rdata    (cpu_mem_rdata),
        .mem_busy     (mem_busy_core),
        .debug_reg_x1 (debug_reg_x1),
        .cpu_halt     (cpu_halt)
    );

    // =========================================================================
    // HARDWARE TIMER
    // =========================================================================
    // The timer is accessed through the local MMIO address space.
    // Timer write transactions require the CPU write-enable signal, a valid
    // timer address, and byte strobe bit 0.

    vrm_cpu_timer_64 sys_timer (
        .clk    (clk),
        .rstn   (rstn),
        .addr   (cpu_mem_addr),
        .wdata  (cpu_mem_wdata),
        .we     (cpu_mem_we && timer_sel && cpu_mem_wstrb[0]),
        .rdata  (timer_rdata),
        .irq_out(timer_irq)
    );

    // =========================================================================
    // INTERRUPT SOURCE ROUTING
    // =========================================================================
    // Interrupt source bit 0 is assigned to the internal hardware timer.
    // External interrupt sources occupy bits 1 through 31 after
    // synchronization.

    wire [31:0] irq_sources;

    assign irq_sources[0]    = timer_irq;
    assign irq_sources[31:1] = ext_irq_sync2;

    // =========================================================================
    // INTERRUPT ARBITER
    // =========================================================================
    // The interrupt arbiter collects pending interrupt sources, applies the
    // configured interrupt-enable mask, and generates the CPU interrupt
    // trigger.

    vrm_cpu_irq_arbiter_64 sys_arbiter (
        .clk             (clk),
        .rstn            (rstn),
        .addr            (cpu_mem_addr),
        .wdata           (cpu_mem_wdata),
        .we              (cpu_mem_we && arbiter_sel && cpu_mem_wstrb[0]),
        .rdata           (arbiter_rdata),
        .irq_src         (irq_sources),
        .cpu_irq_trigger (irq_to_cpu)
    );

    // =========================================================================
    // READ DATA MULTIPLEXER
    // =========================================================================
    // Select read data from the locally addressed peripheral or from external
    // memory for non-local accesses.

    always @(*) begin

        if (timer_sel)
            cpu_mem_rdata = timer_rdata;

        else if (arbiter_sel)
            cpu_mem_rdata = arbiter_rdata;

        else
            cpu_mem_rdata = ext_mem_rdata;

    end

    // =========================================================================
    // EXTERNAL MEMORY INTERFACE
    // =========================================================================
    // CPU memory signals are forwarded to the external memory interface.
    // Write strobes and write-enable are suppressed for local MMIO accesses.

    assign ext_mem_addr  = cpu_mem_addr;
    assign ext_mem_wdata = cpu_mem_wdata;

    assign ext_mem_wstrb = local_access ? 8'h00 : cpu_mem_wstrb;
    assign ext_mem_we    = cpu_mem_we && !local_access;

endmodule
