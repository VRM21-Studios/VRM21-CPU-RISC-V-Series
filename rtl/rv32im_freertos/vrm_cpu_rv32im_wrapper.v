`timescale 1ns / 1ps
`include "vrm_soc_map_rv32i.vh"
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_cpu_rv32im_wrapper
// DESCRIPTION : CPU subsystem: RV32IM core, local timer, and interrupt
//               arbiter behind one address decoder. Every data access outside
//               the timer and arbiter windows is forwarded to the SoC.
//
// Interrupt Behavior:
//   - The timer drives the core MTIP input directly (mcause 7).
//   - Timer and external sources also enter the arbiter; its output drives
//     the core MEIP input (mcause 11).
//   - The software interrupt input is tied low.
//
// Memory Interface:
//   - ext_mem_be carries the byte enables of the core for SB/SH/SW.
//   - ext_mem_we is asserted only for addresses outside the timer and
//     arbiter windows.
// ============================================================================
module vrm_cpu_rv32im_wrapper (
    input  wire        clk,
    input  wire        rstn,

    // Instruction memory interface
    output wire [31:0] pc_out,
    input  wire [31:0] instr_in,

    // External data memory interface
    output wire [31:0] ext_mem_addr,
    output wire [31:0] ext_mem_wdata,
    output wire [3:0]  ext_mem_be,
    output wire        ext_mem_we,
    input  wire [31:0] ext_mem_rdata,

    // External interrupt sources (arbiter bits 1..31; bit 0 is the timer)
    input  wire [30:0] ext_irq_in,

    output wire [31:0] debug_reg_x1,
    output wire        cpu_halt
);

    // -------------------------------------------------------------------------
    // Internal interconnect
    // -------------------------------------------------------------------------
    wire        irq_to_cpu;       // aggregated interrupt from arbiter
    wire        timer_irq;        // hardware timer interrupt

    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_be;
    wire        cpu_mem_we;
    reg  [31:0] cpu_mem_rdata;

    wire [31:0] timer_rdata;
    wire [31:0] arbiter_rdata;

    // -------------------------------------------------------------------------
    // 1. CPU CORE
    // -------------------------------------------------------------------------
    vrm_cpu_rv32im_core core (
        .clk          (clk),
        .rstn         (rstn),

        // Interrupt lines
        .irq_ext      (irq_to_cpu),   // aggregated sources (incl. timer)
        .irq_timer    (timer_irq),    // hardware timer direct (MTIP / cause 7)
        .irq_sw       (1'b0),         // software interrupt unused

        // Instruction memory
        .pc_out       (pc_out),
        .instr_in     (instr_in),

        // Data memory
        .mem_addr     (cpu_mem_addr),
        .mem_wdata    (cpu_mem_wdata),
        .mem_be       (cpu_mem_be),
        .mem_we       (cpu_mem_we),
        .mem_rdata    (cpu_mem_rdata),

        .debug_reg_x1 (debug_reg_x1),
        .cpu_halt     (cpu_halt)
    );

    // -------------------------------------------------------------------------
    // 2. LOCAL ADDRESS DECODER
    // -------------------------------------------------------------------------
    wire timer_sel   = (cpu_mem_addr >= `TIMER_BASE_ADDR) && (cpu_mem_addr < `TIMER_END_ADDR);
    wire arbiter_sel = (cpu_mem_addr >= `IRQ_BASE_ADDR)   && (cpu_mem_addr < `IRQ_END_ADDR);
    wire ext_sel     = !timer_sel && !arbiter_sel;

    // -------------------------------------------------------------------------
    // 3. HARDWARE TIMER
    // -------------------------------------------------------------------------
    vrm_timer sys_timer (
        .clk    (clk),
        .rstn   (rstn),
        .addr   (cpu_mem_addr),
        .wdata  (cpu_mem_wdata),
        .we     (cpu_mem_we && timer_sel),
        .rdata  (timer_rdata),
        .irq_out(timer_irq)
    );

    // -------------------------------------------------------------------------
    // 4. INTERRUPT ARBITER
    // -------------------------------------------------------------------------
    wire [31:0] irq_sources;
    assign irq_sources[0]    = timer_irq;   // bit 0 = hardware timer
    assign irq_sources[31:1] = ext_irq_in;  // bits 1..31 = external

    vrm_irq_arbiter sys_arbiter (
        .clk            (clk),
        .rstn           (rstn),
        .addr           (cpu_mem_addr),
        .wdata          (cpu_mem_wdata),
        .we             (cpu_mem_we && arbiter_sel),
        .rdata          (arbiter_rdata),
        .irq_src        (irq_sources),
        .cpu_irq_trigger(irq_to_cpu)
    );

    // -------------------------------------------------------------------------
    // 5. READ BUS MULTIPLEXER
    // -------------------------------------------------------------------------
    always @(*) begin
        if (timer_sel)        cpu_mem_rdata = timer_rdata;
        else if (arbiter_sel) cpu_mem_rdata = arbiter_rdata;
        else                  cpu_mem_rdata = ext_mem_rdata;
    end

    // -------------------------------------------------------------------------
    // 6. EXTERNAL MEMORY OUTPUT ROUTING
    // -------------------------------------------------------------------------
    assign ext_mem_addr  = cpu_mem_addr;
    assign ext_mem_wdata = cpu_mem_wdata;
    assign ext_mem_be    = cpu_mem_be;
    assign ext_mem_we    = cpu_mem_we && ext_sel;

endmodule
