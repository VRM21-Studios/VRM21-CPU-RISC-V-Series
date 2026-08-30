`timescale 1ns / 1ps
`include "vrm_soc_map_rv32i.vh"

// ============================================================================
// Module      : vrm_cpu_rv32i_wrapper
// Description : System-level wrapper integrating the RV32I CPU core with
//               a hardware timer, interrupt arbiter, and external memory bus.
//
// Features:
// - Integrates vrm_cpu_rv32i_core with system peripherals.
// - Provides a memory-mapped hardware timer.
// - Provides centralized interrupt arbitration.
// - Supports one internal timer interrupt and up to 31 external interrupt
//   sources.
// - Automatically routes MMIO accesses to the appropriate peripheral.
// - Routes all non-peripheral memory accesses to the external memory
//   interface.
// - Uses the shared SoC address map defined in vrm_soc_map_rv32i.vh.
//
// Interrupt Mapping:
// - IRQ bit 0     : Internal hardware timer.
// - IRQ bits 1-31 : External interrupt sources.
//
// Memory-Mapped Peripherals:
// - TIMER_BASE_ADDR .. TIMER_END_ADDR
//     Hardware timer registers.
// - IRQ_BASE_ADDR .. IRQ_END_ADDR
//     Interrupt arbiter registers.
// - Other addresses
//     External memory / accelerator / peripheral space.
//
// Data Path:
//     CPU
//      |
//      +---- Timer MMIO
//      |
//      +---- IRQ Arbiter MMIO
//      |
//      +---- External Memory Interface
//
// Interrupt Path:
//     Timer IRQ ----+
//                  |
//     External ----+--> IRQ Arbiter --> CPU IRQ
//     IRQ Sources
//
// Notes:
// - The wrapper performs local address decoding based on the SoC memory map.
// - Peripheral accesses are consumed internally and are not forwarded to
//   the external memory interface.
// - Non-peripheral accesses are passed through to the external memory bus.
// ============================================================================

module vrm_cpu_rv32i_wrapper(
    input  wire clk,
    input  wire rstn,

    // =========================================================================
    // INSTRUCTION MEMORY INTERFACE
    // =========================================================================
    output wire [31:0] pc_out,
    input  wire [31:0] instr_in,

    // =========================================================================
    // EXTERNAL DATA MEMORY INTERFACE
    // =========================================================================
    // Used for memory and peripherals outside the locally decoded timer and
    // interrupt-controller address ranges.
    output wire [31:0] ext_mem_addr,
    output wire [31:0] ext_mem_wdata,
    output wire        ext_mem_we,
    input  wire [31:0] ext_mem_rdata,

    // =========================================================================
    // EXTERNAL INTERRUPT SOURCES
    // =========================================================================
    // 31 external interrupt sources.
    // IRQ bit 0 is reserved internally for the system timer.
    input  wire [30:0] ext_irq_in,

    // =========================================================================
    // DEBUG / STATUS OUTPUTS
    // =========================================================================
    output wire [31:0] debug_reg_x1,
    output wire        cpu_halt
);

    // =========================================================================
    // INTERNAL CPU / PERIPHERAL SIGNALS
    // =========================================================================
    wire        irq_to_cpu;
    wire        timer_irq;

    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire        cpu_mem_we;

    // Read-data path returned to the CPU core.
    reg  [31:0] cpu_mem_rdata;

    // Peripheral read-data paths.
    wire [31:0] timer_rdata;
    wire [31:0] arbiter_rdata;

    // =========================================================================
    // 1. RV32I CPU CORE
    // =========================================================================
    // The CPU core provides the instruction and data-memory interfaces.
    // Its data-memory transactions are decoded locally by this wrapper.
    vrm_cpu_rv32i_core core (
        .clk(clk),
        .rstn(rstn),
        .irq(irq_to_cpu),

        .pc_out(pc_out),
        .instr_in(instr_in),

        .mem_addr(cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_we(cpu_mem_we),
        .mem_rdata(cpu_mem_rdata),

        .debug_reg_x1(debug_reg_x1),
        .cpu_halt(cpu_halt)
    );

    // =========================================================================
    // 2. LOCAL ADDRESS DECODER
    // =========================================================================
    // Decode the CPU memory address against the system address map.
    //
    // timer_sel:
    //   Selects the hardware timer address range.
    //
    // arbiter_sel:
    //   Selects the interrupt arbiter address range.
    wire timer_sel =
        (cpu_mem_addr >= `TIMER_BASE_ADDR) &&
        (cpu_mem_addr <  `TIMER_END_ADDR);

    wire arbiter_sel =
        (cpu_mem_addr >= `IRQ_BASE_ADDR) &&
        (cpu_mem_addr <  `IRQ_END_ADDR);

    // =========================================================================
    // 3. HARDWARE TIMER
    // =========================================================================
    // The timer is accessed through the CPU MMIO bus and generates the
    // internal timer interrupt source.
    vrm_timer sys_timer (
        .clk(clk),
        .rstn(rstn),

        .addr(cpu_mem_addr),
        .wdata(cpu_mem_wdata),
        .we(cpu_mem_we && timer_sel),

        .rdata(timer_rdata),
        .irq_out(timer_irq)
    );

    // =========================================================================
    // 4. INTERRUPT SOURCE AGGREGATION
    // =========================================================================
    // Combine the internal timer interrupt and external interrupt sources
    // into the 32-bit interrupt source bus expected by vrm_irq_arbiter.
    //
    // Bit 0:
    //   Internal system timer.
    //
    // Bits 1-31:
    //   External interrupt inputs.
    wire [31:0] irq_sources;

    assign irq_sources[0]    = timer_irq;
    assign irq_sources[31:1] = ext_irq_in;

    // =========================================================================
    // 5. INTERRUPT ARBITER
    // =========================================================================
    // Provides interrupt pending/enable management and generates the final
    // interrupt request delivered to the CPU core.
    vrm_irq_arbiter sys_arbiter (
        .clk(clk),
        .rstn(rstn),

        .addr(cpu_mem_addr),
        .wdata(cpu_mem_wdata),
        .we(cpu_mem_we && arbiter_sel),

        .rdata(arbiter_rdata),

        .irq_src(irq_sources),
        .cpu_irq_trigger(irq_to_cpu)
    );

    // =========================================================================
    // 6. CPU READ-DATA BUS MULTIPLEXER
    // =========================================================================
    // Select the read-data source based on the decoded CPU address.
    //
    // Priority:
    // 1. Timer
    // 2. Interrupt arbiter
    // 3. External memory
    //
    // Peripheral reads are therefore handled locally and do not depend on
    // the external memory interface.
    always @(*) begin
        if (timer_sel)
            cpu_mem_rdata = timer_rdata;
        else if (arbiter_sel)
            cpu_mem_rdata = arbiter_rdata;
        else
            cpu_mem_rdata = ext_mem_rdata;
    end

    // =========================================================================
    // 7. EXTERNAL MEMORY BUS ROUTING
    // =========================================================================
    // Forward CPU memory transactions that do not target the locally
    // integrated timer or interrupt arbiter.
    //
    // Peripheral write transactions are consumed internally and therefore
    // prevented from reaching the external memory interface.
    assign ext_mem_addr  = cpu_mem_addr;
    assign ext_mem_wdata = cpu_mem_wdata;
    assign ext_mem_we    = cpu_mem_we && !timer_sel && !arbiter_sel;

endmodule
