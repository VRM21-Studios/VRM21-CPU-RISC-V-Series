`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_bootloader
// DESCRIPTION : Hardware bootloader. Copies an initialized firmware image into
//               the SoC RAM through a dedicated write port, optionally writes
//               a two-instruction reset trampoline at address 0, and then
//               releases the CPU.
//
// Features:
//   - Image read at elaboration from "firmware.mem" (byte-per-token hex as
//     produced by objcopy -O verilog, packed little-endian into words).
//   - One word written per clock cycle starting at FIRMWARE_BASE_ADDR.
//   - RESET_TRAMPOLINE = 1 writes "lui t0, hi(base); jalr x0, lo(base)(t0)"
//     at 0x0 and 0x4 so that the reset vector jumps to the loaded image.
//
// Memory Interface:
//   boot_mem_we / boot_mem_addr / boot_mem_wdata form a registered write
//   port. Each beat is a full 32-bit word.
//
// Notes:
//   - FIRMWARE_BYTES bounds the image. The SoC top selects 16384 bytes at
//     0x1000_1000 for the FreeRTOS autoboot image and 4096 bytes at 0x0 for
//     the legacy boot mode. An image larger than FIRMWARE_BYTES makes
//     $readmemh report out-of-range addresses.
//   - "firmware.mem" is resolved relative to the simulator run directory, or
//     by name among the design sources in Vivado synthesis.
// ============================================================================

module vrm_bootloader #(
    parameter integer FIRMWARE_BYTES = 4096,
    parameter integer RAM_ADDR_WIDTH = 16,
    parameter [31:0] FIRMWARE_BASE_ADDR = 32'h0000_0000,
    parameter RESET_TRAMPOLINE = 1'b0
)(
    input  wire clk,
    input  wire rstn,

    // ------------------------------------------------------------------------
    // Boot memory write interface
    // ------------------------------------------------------------------------
    output reg          boot_mem_we,
    output reg [31:0]   boot_mem_addr,
    output reg [31:0]   boot_mem_wdata,

    // ------------------------------------------------------------------------
    // Boot status
    // ------------------------------------------------------------------------
    output reg          boot_done,
    output reg          cpu_release
);

    // Number of 32-bit words in firmware.
    localparam integer FIRMWARE_WORDS = (FIRMWARE_BYTES + 3) / 4;
    localparam integer STORAGE_BYTES = FIRMWARE_WORDS * 4;
    // lui t0, base[31:12]; jalr x0, base[11:0](t0).
    // Round up the LUI immediate when the signed JALR offset is negative.
    localparam [31:0] LUI_BASE = FIRMWARE_BASE_ADDR + 32'h0000_0800;

    // =========================================================================
    // 1. FIRMWARE MEMORY (32-BIT PACKED)
    // =========================================================================
    reg [31:0] firmware_mem [0:FIRMWARE_WORDS-1];

    // Byte image as read from the file; only used during initialization.
    reg [7:0] temp_mem [0:STORAGE_BYTES-1];

    integer i;

    initial begin
        // Bytes not present in the file read as zero.
        for (i = 0; i < STORAGE_BYTES; i = i + 1)
            temp_mem[i] = 8'h00;

        $readmemh("firmware.mem", temp_mem);

        // Pack four bytes per word, little-endian. Synthesis evaluates this
        // loop as the initial value of firmware_mem and drops temp_mem.
        for (i = 0; i < FIRMWARE_WORDS; i = i + 1) begin
            firmware_mem[i] = {
                temp_mem[(i*4) + 3],
                temp_mem[(i*4) + 2],
                temp_mem[(i*4) + 1],
                temp_mem[(i*4) + 0]
            };
        end
    end

    // =========================================================================
    // 2. BOOT STATE MACHINE
    // =========================================================================
    // BOOT_LOAD      : write one image word per cycle until the last word.
    // BOOT_RESET_LUI : write the LUI of the trampoline at 0x0.
    // BOOT_RESET_JR  : write the JALR of the trampoline at 0x4.
    // BOOT_DONE      : assert boot_done and cpu_release and stay here.
    // Without RESET_TRAMPOLINE, BOOT_LOAD goes directly to BOOT_DONE.
    localparam [1:0]
        BOOT_LOAD = 2'd0,
        BOOT_RESET_LUI = 2'd1,
        BOOT_RESET_JR  = 2'd2,
        BOOT_DONE = 2'd3;

    reg [1:0] state;
    integer word_count;

    // =========================================================================
    // 3. BOOT SEQUENCER
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            state          <= BOOT_LOAD;
            word_count     <= 0;

            boot_mem_we    <= 1'b0;
            boot_mem_addr  <= FIRMWARE_BASE_ADDR;
            boot_mem_wdata <= 32'h0000_0000;

            boot_done      <= 1'b0;
            cpu_release    <= 1'b0;

        end else begin
            // Default: write enable is a one-cycle pulse.
            boot_mem_we <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // LOAD FIRMWARE
                // -------------------------------------------------------------
                BOOT_LOAD: begin
                    boot_mem_we    <= 1'b1;
                    boot_mem_addr  <= FIRMWARE_BASE_ADDR + (word_count * 4);
                    boot_mem_wdata <= firmware_mem[word_count];
                    word_count     <= word_count + 1;

                    if (word_count == FIRMWARE_WORDS - 1) begin
                        state <= RESET_TRAMPOLINE ? BOOT_RESET_LUI : BOOT_DONE;
                    end
                end

                BOOT_RESET_LUI: begin
                    boot_mem_we    <= 1'b1;
                    boot_mem_addr  <= 32'h0000_0000;
                    boot_mem_wdata <= {LUI_BASE[31:12], 5'd5, 7'h37};
                    state          <= BOOT_RESET_JR;
                end

                BOOT_RESET_JR: begin
                    boot_mem_we    <= 1'b1;
                    boot_mem_addr  <= 32'h0000_0004;
                    boot_mem_wdata <= {FIRMWARE_BASE_ADDR[11:0], 5'd5, 3'd0, 5'd0, 7'h67};
                    state          <= BOOT_DONE;
                end

                // -------------------------------------------------------------
                // BOOT COMPLETE
                // -------------------------------------------------------------
                BOOT_DONE: begin
                    // RAM accepts the last registered write on this edge.
                    boot_done   <= 1'b1;
                    cpu_release <= 1'b1;
                    state       <= BOOT_DONE;
                end

                default: begin
                    state <= BOOT_LOAD;
                end

            endcase
        end
    end

endmodule
