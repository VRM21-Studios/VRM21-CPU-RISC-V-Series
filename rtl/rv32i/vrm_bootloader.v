`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_bootloader
// Description : Hardware firmware loader for the VRM21 RV32I SoC.
//
//               The bootloader stores a firmware image in an internally
//               initialized memory array and sequentially transfers the image
//               to the system boot memory after reset.
//
//               Firmware bytes are pre-packed into 32-bit little-endian words
//               before being accessed by the boot sequencer.
//
// Operation:
//   1. Wait for reset deassertion.
//   2. Sequentially write each firmware word to boot memory.
//   3. Assert boot_done and cpu_release after the complete firmware image
//      has been transferred.
//
// Notes:
// - The firmware image is loaded from "firmware.mem" during initialization.
// - The input firmware file is interpreted as an array of 8-bit values.
// - Four consecutive bytes are packed into one 32-bit little-endian word.
// - boot_mem_we is asserted for one clock cycle for each firmware word.
// - cpu_release remains asserted after the boot process is complete.
// ============================================================================

module vrm_bootloader #(
parameter integer FIRMWARE_BYTES     = 4096,
parameter integer RAM_ADDR_WIDTH     = 16,
parameter [31:0] FIRMWARE_BASE_ADDR = 32'h0000_0000
)(
input  wire clk,
input  wire rstn,


// ------------------------------------------------------------------------
// BOOT MEMORY WRITE INTERFACE
// ------------------------------------------------------------------------
output reg          boot_mem_we,
output reg [31:0]   boot_mem_addr,
output reg [31:0]   boot_mem_wdata,

// ------------------------------------------------------------------------
// BOOT STATUS
// ------------------------------------------------------------------------
output reg          boot_done,
output reg          cpu_release


);


// =========================================================================
// FIRMWARE CONFIGURATION
// =========================================================================

// Number of 32-bit words required to store the complete firmware image.
localparam integer FIRMWARE_WORDS = (FIRMWARE_BYTES + 3) / 4;


// =========================================================================
// FIRMWARE MEMORY
// =========================================================================
//
// The firmware image is stored as packed 32-bit words for efficient
// sequential transfer to the system boot memory.
// -------------------------------------------------------------------------

reg [31:0] firmware_mem [0:FIRMWARE_WORDS-1];

// Temporary byte-addressable memory used to load the firmware image before
// packing four consecutive bytes into each 32-bit firmware word.
reg [7:0] temp_mem [0:FIRMWARE_BYTES-1];

integer i;

initial begin

    // ---------------------------------------------------------------------
    // INITIALIZE TEMPORARY FIRMWARE MEMORY
    // ---------------------------------------------------------------------
    // Clear the temporary byte array before loading the firmware file.

    for (i = 0; i < FIRMWARE_BYTES; i = i + 1)
        temp_mem[i] = 8'h00;

    // ---------------------------------------------------------------------
    // LOAD FIRMWARE IMAGE
    // ---------------------------------------------------------------------
    // Load the hexadecimal firmware image as individual 8-bit values.

    $readmemh("firmware.mem", temp_mem);

    // ---------------------------------------------------------------------
    // PACK FIRMWARE WORDS
    // ---------------------------------------------------------------------
    // Pack four consecutive bytes into one 32-bit little-endian word.
    //
    // Byte layout:
    //
    //   firmware_mem[i][7:0]   = temp_mem[(i * 4) + 0]
    //   firmware_mem[i][15:8]  = temp_mem[(i * 4) + 1]
    //   firmware_mem[i][23:16] = temp_mem[(i * 4) + 2]
    //   firmware_mem[i][31:24] = temp_mem[(i * 4) + 3]

    for (i = 0; i < FIRMWARE_WORDS; i = i + 1) begin
        firmware_mem[i] = {
            temp_mem[(i * 4) + 3],
            temp_mem[(i * 4) + 2],
            temp_mem[(i * 4) + 1],
            temp_mem[(i * 4) + 0]
        };
    end
end


// =========================================================================
// BOOT STATE MACHINE
// =========================================================================

localparam [1:0]
    BOOT_LOAD = 2'd0,
    BOOT_DONE = 2'd1;

reg [1:0] state;
integer   word_count;


// =========================================================================
// BOOT SEQUENCER
// =========================================================================

always @(posedge clk) begin

    if (!rstn) begin

        // -----------------------------------------------------------------
        // RESET STATE
        // -----------------------------------------------------------------

        state          <= BOOT_LOAD;
        word_count     <= 0;

        boot_mem_we    <= 1'b0;
        boot_mem_addr  <= FIRMWARE_BASE_ADDR;
        boot_mem_wdata <= 32'h0000_0000;

        boot_done      <= 1'b0;
        cpu_release    <= 1'b0;

    end else begin

        // -----------------------------------------------------------------
        // DEFAULT WRITE ENABLE
        // -----------------------------------------------------------------
        // The memory write enable is generated as a one-clock-cycle pulse
        // for each firmware word transfer.

        boot_mem_we <= 1'b0;

        case (state)

            // =============================================================
            // BOOT LOAD
            // =============================================================
            // Sequentially transfer the packed firmware image to the
            // system boot memory.

            BOOT_LOAD: begin

                // Assert the boot memory write enable.
                boot_mem_we <= 1'b1;

                // Generate the byte-addressed destination address.
                boot_mem_addr <= FIRMWARE_BASE_ADDR +
                                 (word_count * 4);

                // Transfer the current 32-bit firmware word.
                boot_mem_wdata <= firmware_mem[word_count];

                // Advance to the next firmware word.
                word_count <= word_count + 1;

                // Transition to the completion state after transferring
                // the final firmware word.
                if (word_count == FIRMWARE_WORDS - 1) begin
                    state <= BOOT_DONE;
                end
            end


            // =============================================================
            // BOOT COMPLETE
            // =============================================================
            // The complete firmware image has been transferred.
            // Release the CPU and remain in this state permanently.

            BOOT_DONE: begin

                boot_done   <= 1'b1;
                cpu_release <= 1'b1;

                state       <= BOOT_DONE;
            end


            // =============================================================
            // DEFAULT
            // =============================================================
            // Recover from an undefined state by restarting the boot
            // sequence.

            default: begin
                state <= BOOT_LOAD;
            end

        endcase
    end
end

endmodule
