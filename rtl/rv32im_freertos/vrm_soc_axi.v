`timescale 1ns / 1ps
`include "vrm_soc_map_rv32i.vh"
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_soc_axi
// DESCRIPTION : AXI4-Lite and AXI4-Stream top of the RV32IM + VCF SoC. Holds
//               the hardware bootloader, the CPU control register, and the
//               host access path into vrm_soc_top.
//
// Features:
//   - BOOT_FREERTOS = 1 (default): the bootloader copies a 16 KiB image slot
//     from firmware.mem to 0x1000_1000, writes a reset trampoline at 0x0/0x4,
//     and releases the CPU. No host action is needed for a cold boot.
//   - BOOT_FREERTOS = 0: legacy mode, a 4 KiB image is copied to 0x0.
//   - AXI4-Lite gives the host access to RAM, VCF registers, and CPU_CTRL.
//   - AXI4-Stream audio passes through the VCF (s_axis in, m_axis out).
//
// Boot Flow:
//   reset -> vrm_bootloader copies firmware.mem -> boot_done
//         -> CPU released -> AXI-Lite runtime control
//
// Registers (AXI4-Lite offsets; the slave decodes the full 32-bit offset):
//   0x0000_0000-0x0000_0FFF  ROM window (alias of the first 4 KiB of RAM)
//   0x0000_C000              CPU_CTRL: [0] 0 = hold CPU in reset, 1 = run
//                            (reset value 1)
//   0x1000_0000-0x1000_FFFF  RAM
//   0x8000_2000-0x8000_200C  VCF CTRL / CUTOFF / RES / LCO
//
// Notes:
//   - Writes are full words; WSTRB is ignored. BRESP and RRESP are OKAY.
//   - Reads are sampled one cycle after the address handshake.
//   - The host must be given an address window of at least 0x8000_2010 bytes
//     (the reference block design assigns 4 GB).
//   - WARNING: CPU_CTRL is matched on address bits [15:0] only, so a host
//     write to any address whose low 16 bits equal 0xC000 (for example RAM
//     0x1000_C000) updates CPU_CTRL instead of memory.
//   - Clock and reset carry interface attributes for Vivado; no clock
//     frequency is fixed in the RTL.
// ============================================================================

module vrm_soc_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXIS_IN_WIDTH    = 32,
    parameter integer C_AXIS_OUT_WIDTH   = 32,
    parameter BOOT_FREERTOS = 1'b1
)(
    // =========================================================================
    // GLOBAL SIGNALS
    // =========================================================================

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis:m_axis,ASSOCIATED_RESET s_axi_aresetn" *)
    input wire s_axi_aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire s_axi_aresetn,


    // =========================================================================
    // AXI4-LITE WRITE CHANNEL
    // =========================================================================

    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire                          s_axi_awvalid,
    output reg                          s_axi_awready,

    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input wire                            s_axi_wvalid,
    output reg                            s_axi_wready,

    output wire [1:0] s_axi_bresp,
    output reg        s_axi_bvalid,
    input wire        s_axi_bready,


    // =========================================================================
    // AXI4-LITE READ CHANNEL
    // =========================================================================

    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire                          s_axi_arvalid,
    output reg                          s_axi_arready,

    output reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input wire                          s_axi_rready,


    // =========================================================================
    // AXI4-STREAM AUDIO INPUT
    // =========================================================================

    input wire [C_AXIS_IN_WIDTH-1:0] s_axis_tdata,
    input wire                       s_axis_tvalid,
    input wire                       s_axis_tlast,
    output wire                      s_axis_tready,


    // =========================================================================
    // AXI4-STREAM AUDIO OUTPUT
    // =========================================================================

    output wire [C_AXIS_OUT_WIDTH-1:0] m_axis_tdata,
    output wire                        m_axis_tvalid,
    output wire                        m_axis_tlast,
    input wire                         m_axis_tready,


    // =========================================================================
    // SYSTEM / DEBUG
    // =========================================================================

    input wire [30:0] ext_irq_in,

    output wire        cpu_halt,
    output wire [31:0] cpu_pc,
    output wire [31:0] debug_reg_x1
);


    // =========================================================================
    // 1. AXI RESPONSE SIGNALS
    // =========================================================================

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;


    // =========================================================================
    // 2. CPU CONTROL REGISTER
    // =========================================================================
    //
    // Bit[0]: 0 = CPU held in reset, 1 = CPU running.
    //
    // The reset value is 1 because the bootloader already gates CPU startup:
    // while boot_done/cpu_release are low the CPU stays in reset, and it
    // starts automatically after boot. The host writes 0 to halt the CPU,
    // for example before loading a new image, and 1 to restart it.
    //
    // =========================================================================

    localparam [31:0] ADDR_CTRL_REG =
        32'h0000_C000;

    reg [31:0] reg_cpu_ctrl;


    // =========================================================================
    // 3. AXI WRITE STATE
    // =========================================================================

    reg aw_en;
    reg w_en;

    reg ram_we_pulse;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_wdata;


    // =========================================================================
    // 4. AXI WRITE FSM
    // =========================================================================
    // Address and data are captured independently; the write is executed and
    // BVALID raised once both have arrived. A non-CPU_CTRL write becomes a
    // one-cycle host write pulse into vrm_soc_top.

    always @(posedge s_axi_aclk) begin

        if (!s_axi_aresetn) begin

            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;

            aw_en <= 1'b1;
            w_en  <= 1'b1;

            axi_awaddr <= 32'h00000000;
            axi_wdata  <= 32'h00000000;

            // CPU logically enabled; vrm_soc_top still holds it in reset
            // until boot completion.
            reg_cpu_ctrl <= 32'h00000001;

            ram_we_pulse <= 1'b0;

        end else begin

            ram_we_pulse <= 1'b0;


            // -----------------------------------------------------------------
            // Capture write address
            // -----------------------------------------------------------------

            if (!s_axi_awready &&
                s_axi_awvalid &&
                aw_en) begin

                s_axi_awready <= 1'b1;
                aw_en         <= 1'b0;
                axi_awaddr    <= s_axi_awaddr;

            end else begin

                s_axi_awready <= 1'b0;

            end


            // -----------------------------------------------------------------
            // Capture write data
            // -----------------------------------------------------------------

            if (!s_axi_wready &&
                s_axi_wvalid &&
                w_en) begin

                s_axi_wready <= 1'b1;
                w_en         <= 1'b0;
                axi_wdata    <= s_axi_wdata;

            end else begin

                s_axi_wready <= 1'b0;

            end


            // -----------------------------------------------------------------
            // Complete AXI write transaction
            // -----------------------------------------------------------------

            if (s_axi_bready && s_axi_bvalid) begin

                s_axi_bvalid <= 1'b0;

                aw_en <= 1'b1;
                w_en  <= 1'b1;

            end else if (!aw_en &&
                         !w_en &&
                         !s_axi_bvalid) begin

                s_axi_bvalid <= 1'b1;

                if (axi_awaddr[15:0] ==
                    ADDR_CTRL_REG[15:0]) begin

                    reg_cpu_ctrl <= axi_wdata;

                end else begin

                    // One-cycle host write pulse. vrm_soc_top ignores it
                    // while the bootloader is still active.
                    ram_we_pulse <= 1'b1;

                end

            end

        end
    end


    // =========================================================================
    // 5. AXI READ STATE
    // =========================================================================

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg ram_re_pulse;

    reg [2:0] read_state;

    localparam R_IDLE    = 3'd0;
    localparam R_WAIT    = 3'd1;
    localparam R_CAPTURE = 3'd2;
    localparam R_SEND    = 3'd3;


    // -------------------------------------------------------------------------
    // Host address mux
    // -------------------------------------------------------------------------
    //
    // During a write transaction, preserve the captured write address.
    // Otherwise use the current read address.
    //
    // -------------------------------------------------------------------------

    wire [31:0] mux_host_addr =
        (aw_en == 1'b0) ? axi_awaddr :
                          axi_araddr;
    wire [31:0] soc_host_rdata;


    // =========================================================================
    // 6. AXI READ FSM
    // =========================================================================
    // R_IDLE : accept ARADDR; pulse host_re for a non-CPU_CTRL address
    // R_WAIT : sample CPU_CTRL or the SoC read data in the pulse cycle
    // R_SEND : hold RVALID until RREADY
    // R_CAPTURE is declared but not used.

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h00000000;
            axi_araddr    <= 32'h00000000;
            ram_re_pulse  <= 1'b0;
            read_state    <= R_IDLE;
        end else begin
            case (read_state)
                R_IDLE: begin
                    if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid) begin
                        s_axi_arready <= 1'b1;
                        axi_araddr    <= s_axi_araddr;

                        if (s_axi_araddr[15:0] != ADDR_CTRL_REG[15:0]) begin
                            ram_re_pulse <= 1'b1;
                        end
                        read_state <= R_WAIT;
                    end
                end

                R_WAIT: begin
                    s_axi_arready <= 1'b0;
                    ram_re_pulse  <= 1'b0; // pulse lasts one cycle

                    if (axi_araddr[15:0] == ADDR_CTRL_REG[15:0]) begin
                        s_axi_rdata <= reg_cpu_ctrl;
                    end else begin
                        s_axi_rdata <= soc_host_rdata; // sampled while host_re is high
                    end
                    read_state  <= R_SEND;
                end

                R_SEND: begin
                    s_axi_rvalid <= 1'b1;
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        read_state   <= R_IDLE;
                    end
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

    // =========================================================================
    // 7. HARDWARE BOOTLOADER
    // =========================================================================
    //
    // The bootloader has a dedicated initialization path into vrm_soc_top.
    // It loads firmware.mem into the unified RAM before the CPU is released.
    //
    // =========================================================================

    wire        boot_mem_we;
    wire [31:0] boot_mem_addr;
    wire [31:0] boot_mem_wdata;

    wire boot_done;
    wire cpu_release;


    vrm_bootloader #(
        .FIRMWARE_BYTES    (BOOT_FREERTOS ? 16384 : 4096),
        .RAM_ADDR_WIDTH    (16),
        .FIRMWARE_BASE_ADDR(BOOT_FREERTOS ? 32'h1000_1000 : 32'h0000_0000),
        .RESET_TRAMPOLINE  (BOOT_FREERTOS)
    ) u_bootloader (
        .clk          (s_axi_aclk),
        .rstn         (s_axi_aresetn),

        .boot_mem_we   (boot_mem_we),
        .boot_mem_addr (boot_mem_addr),
        .boot_mem_wdata(boot_mem_wdata),

        .boot_done     (boot_done),
        .cpu_release   (cpu_release)
    );


    // =========================================================================
    // 8. VRM SOC
    // =========================================================================
    // The host interface stays connected. vrm_soc_top decides which requester
    // owns the RAM write port: the bootloader during boot, the host during an
    // AXI-Lite write, and the CPU otherwise.

    vrm_soc_top #(
        .C_AXIS_IN_WIDTH (C_AXIS_IN_WIDTH),
        .C_AXIS_OUT_WIDTH(C_AXIS_OUT_WIDTH)
    ) vrm_soc_inst (

        .clk       (s_axi_aclk),

        .sys_rstn  (s_axi_aresetn),

        // Runtime CPU control from AXI-Lite; during boot vrm_soc_top also
        // gates the CPU with boot_done/cpu_release.
        .rstn      (reg_cpu_ctrl[0]),


        // Host / AXI-Lite
        .host_we   (ram_we_pulse),
        .host_re   (ram_re_pulse),
        .host_addr (mux_host_addr),
        .host_wdata(axi_wdata),
        .host_rdata(soc_host_rdata),


        // Bootloader
        .boot_mem_we   (boot_mem_we),
        .boot_mem_addr (boot_mem_addr),
        .boot_mem_wdata(boot_mem_wdata),

        .boot_done  (boot_done),
        .cpu_release(cpu_release),


        // Interrupts
        .ext_irq_in(ext_irq_in),


        // AXI-Stream input
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast (s_axis_tlast),
        .s_axis_tready(s_axis_tready),


        // AXI-Stream output
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tready(m_axis_tready),


        // Debug
        .cpu_halt    (cpu_halt),
        .cpu_pc      (cpu_pc),
        .debug_reg_x1(debug_reg_x1)
    );

endmodule
