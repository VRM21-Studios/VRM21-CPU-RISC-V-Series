`timescale 1ns / 1ps
`include "vrm_soc_map_rv32i.vh"
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_soc_top
// DESCRIPTION : Audio-effects SoC core: RV32IM CPU subsystem, 64 KiB unified
//               RAM, and the stereo VCF on the CPU MMIO bus and on the
//               AXI4-Stream audio path.
//
// Features:
//   - One arbitrated write port shared by bootloader, host, and CPU
//     (priority: boot, then host, then CPU).
//   - Separate combinational read paths for CPU data, instruction fetch,
//     and host reads, so a host read never takes the CPU bus.
//   - Byte enables from the CPU for SB/SH/SW; boot and host write full words.
//   - Audio: s_axis (DMA MM2S) -> VCF -> m_axis (DMA S2MM),
//     32-bit packed stereo {R[31:16], L[15:0]}.
//
// Memory Interface:
//   - RAM 0x1000_0000-0x1000_FFFF (16384 words). The ROM window
//     0x0000_0000-0x0000_0FFF aliases the first 4 KiB of the same array.
//   - VCF registers at VCF_BASE_ADDR (0x8000_2000).
//   - The oscillator window (0x8000_1000) is reserved and not decoded:
//     writes are ignored and reads return 0.
//
// Notes:
//   - The RAM is read combinationally on three ports, so Vivado maps it to
//     distributed RAM (LUTRAM), not block RAM.
//   - An instruction fetch outside ROM/RAM returns 0x0000_0000, which the
//     core decodes as an illegal instruction (mcause 2).
//   - WARNING: a host write and a CPU store in the same cycle are not
//     retried; the CPU store is dropped. Hold the CPU (CPU_CTRL = 0) before
//     host writes that may overlap CPU data accesses.
// ============================================================================
module vrm_soc_top #(
    // The VCF datapath is fixed at 32-bit packed stereo. These parameters are
    // kept only for port compatibility with vrm_soc_axi; leave them at 32.
    parameter integer C_AXIS_IN_WIDTH  = 32,
    parameter integer C_AXIS_OUT_WIDTH = 32
)(
    input  wire clk,
    input  wire sys_rstn,
    input  wire rstn,

    // ---- Host (AXI-Lite) interface ----
    input  wire        host_we,
    input  wire        host_re,           // one-cycle read pulse from AXI
    input  wire [31:0] host_addr,
    input  wire [31:0] host_wdata,
    output wire [31:0] host_rdata,

    input  wire [30:0] ext_irq_in,

    input  wire        boot_mem_we,
    input  wire [31:0] boot_mem_addr,
    input  wire [31:0] boot_mem_wdata,

    input  wire        boot_done,
    input  wire        cpu_release,

    input  wire [C_AXIS_IN_WIDTH-1:0] s_axis_tdata,
    input  wire                       s_axis_tvalid,
    input  wire                       s_axis_tlast,
    output wire                       s_axis_tready,

    output wire [C_AXIS_OUT_WIDTH-1:0] m_axis_tdata,
    output wire                        m_axis_tvalid,
    output wire                        m_axis_tlast,
    input  wire                        m_axis_tready,

    output wire        cpu_halt,
    output wire [31:0] cpu_pc,
    output wire [31:0] debug_reg_x1
);

    wire [31:0] cpu_mem_addr, cpu_mem_wdata, cpu_mem_rdata;
    wire        cpu_mem_we;
    wire [3:0]  cpu_mem_be;

    // =========================================================================
    // 1. DATA BUS ARBITRATION
    // =========================================================================
    wire boot_active = !boot_done;
    wire grant_boot  = boot_active && boot_mem_we;
    // A host write uses the shared write port. Host reads have their own path.
    wire grant_host  = boot_done && host_we;
    wire grant_cpu   = boot_done && !grant_host;

    wire [31:0] sb_addr  = grant_boot ? boot_mem_addr :
                           grant_host ? host_addr   :
                           cpu_mem_addr;
    wire [31:0] sb_wdata = grant_boot ? boot_mem_wdata :
                           grant_host ? host_wdata   :
                           cpu_mem_wdata;
    wire sb_we = grant_boot ? boot_mem_we :
                 grant_host ? host_we :
                 (grant_cpu && cpu_mem_we && rstn);

    // =========================================================================
    // 2. UNIFIED RAM (1 write port, separate data/fetch/host reads)
    // =========================================================================
    // NOTE: ROM (0x0000_0000) and RAM (0x1000_0000) alias onto the same word
    // array through sb_addr[15:2]. The linker script must keep .text, .data,
    // .bss, and the stacks in non-overlapping offsets of this array.
    reg [31:0] ram [0:16383];
    integer m;
    initial for (m=0; m<16384; m=m+1) ram[m] = 32'h0;

    // Address decode
    wire sel_rom = (sb_addr >= `ROM_BASE_ADDR) && (sb_addr < `ROM_END_ADDR);
    wire sel_ram = (sb_addr >= `RAM_BASE_ADDR) && (sb_addr < `RAM_END_ADDR);
    wire sel_mem = sel_rom | sel_ram;
    wire sel_vcf = (sb_addr >= `VCF_BASE_ADDR) && (sb_addr < `VCF_END_ADDR);
    wire host_sel_mem = (host_addr < `ROM_END_ADDR) ||
                        ((host_addr >= `RAM_BASE_ADDR) && (host_addr < `RAM_END_ADDR));
    wire host_sel_vcf = (host_addr >= `VCF_BASE_ADDR) && (host_addr < `VCF_END_ADDR);

    // Port 1: synchronous write (arbitrated), per-byte lanes
    wire [3:0] sb_be = (grant_boot || grant_host) ? 4'b1111 : cpu_mem_be;
    integer lane;
    always @(posedge clk)
        if (sb_we && sel_mem)
            for (lane = 0; lane < 4; lane = lane + 1)
                if (sb_be[lane])
                    ram[sb_addr[15:2]][lane*8 +: 8] <= sb_wdata[lane*8 +: 8];

    // Port 2: combinational data read (arbitrated address)
    wire [31:0] rdata_ram = ram[sb_addr[15:2]];

    // Port 3: combinational instruction fetch (dedicated, never arbitrated).
    // An out-of-range PC fetches 0x0000_0000, which traps as illegal.
    wire sel_cpu_pc_mem = (cpu_pc >= `ROM_BASE_ADDR && cpu_pc < `ROM_END_ADDR) ||
                          (cpu_pc >= `RAM_BASE_ADDR && cpu_pc < `RAM_END_ADDR);

    wire [31:0] instr_fetched = sel_cpu_pc_mem ? ram[cpu_pc[15:2]] : 32'h00000000;

    // =========================================================================
    // 3. VCF INSTANCE
    // =========================================================================
    //   MMIO : shares sb_addr / sb_wdata / sb_we, selected by sel_vcf.
    //          Host reads use the separate host_read_* port.
    //   Audio: s_axis (raw stereo) -> VCF -> m_axis.
    // =========================================================================
    wire [31:0] vcf_rdata, host_vcf_rdata;

    vrm_vcf_mmio vcf_inst (
        .clk          (clk),
        .rstn         (sys_rstn),

        .mmio_cs      (sel_vcf),
        .mmio_we      (sb_we),
        .mmio_addr    (sb_addr[5:2]),
        .mmio_wdata   (sb_wdata),
        .mmio_rdata   (vcf_rdata),
        .host_read_addr(host_addr[5:2]),
        .host_read_data(host_vcf_rdata),

        .s_axis_tdata (s_axis_tdata[31:0]),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast (s_axis_tlast),
        .s_axis_tready(s_axis_tready),

        .m_axis_tdata (m_axis_tdata[31:0]),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tready(m_axis_tready)
    );

    // =========================================================================
    // 4. READ DATA MULTIPLEXER
    // =========================================================================
    wire [31:0] sys_rdata = sel_mem ? rdata_ram :
                            sel_vcf ? vcf_rdata :
                            32'h0;

    // The AXI read pulse samples its own decoded data without stealing the CPU bus.
    assign host_rdata = (!boot_done || !host_re) ? 32'h0 :
                        host_sel_mem ? ram[host_addr[15:2]] :
                        host_sel_vcf ? host_vcf_rdata : 32'h0;
    assign cpu_mem_rdata = sys_rdata;

    // =========================================================================
    // 5. CPU SUBSYSTEM
    // =========================================================================
    // The CPU stays in reset until the bootloader has finished and while the
    // host holds CPU_CTRL[0] low.
    wire soc_cpu_rstn = boot_done && cpu_release && rstn;

    vrm_cpu_rv32im_wrapper cpu_sys_inst (
        .clk           (clk),
        .rstn          (soc_cpu_rstn),
        .pc_out        (cpu_pc),
        .instr_in      (instr_fetched), // dedicated fetch port
        .ext_mem_addr  (cpu_mem_addr),
        .ext_mem_wdata (cpu_mem_wdata),
        .ext_mem_be    (cpu_mem_be),
        .ext_mem_we    (cpu_mem_we),
        .ext_mem_rdata (cpu_mem_rdata), // arbitrated data read port
        .ext_irq_in    (ext_irq_in),
        .debug_reg_x1  (debug_reg_x1),
        .cpu_halt      (cpu_halt)
    );

endmodule
