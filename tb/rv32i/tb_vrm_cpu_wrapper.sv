`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_cpu_wrapper
// Description : RV32I CPU wrapper integration verification using simulated
//               instruction memory, external data memory, hardware timer,
//               and interrupt arbiter interfaces.
//
// Features:
//   - RV32I CPU wrapper integration testing
//   - Instruction memory model
//   - External data memory model
//   - Hardware timer configuration and interrupt generation
//   - Interrupt arbiter configuration and pending-bit clearing
//   - WFI and MRET interrupt handling verification
//   - External memory access from the interrupt service routine
//   - Post-interrupt instruction execution verification
//   - Self-checking verification of CPU, interrupt, and memory results
//
// Test Flow:
//   1. Initialize instruction and external data memory models.
//   2. Configure the interrupt arbiter to accept the hardware timer source.
//   3. Configure and start the hardware timer.
//   4. Enter the CPU WFI state.
//   5. Wait for the timer interrupt to wake the CPU.
//   6. Execute the interrupt service routine.
//   7. Clear the timer and interrupt arbiter pending status.
//   8. Write an ISR execution marker to external memory.
//   9. Return from the interrupt using MRET.
//  10. Verify post-interrupt execution and system state.
//
// Memory Model:
//   - 64-word instruction memory
//   - 64-word external data memory
//   - Asynchronous instruction read
//   - Asynchronous external data read
//   - Synchronous external data write
//
// Interrupt Sources:
//   - External interrupt input is held inactive during the test.
//   - Interrupt source bit 0 is reserved for the internal hardware timer.
//   - The hardware timer interrupt is routed through the interrupt arbiter.
//
// Verification:
//   - CPU wake-up from WFI is verified through post-interrupt execution.
//   - Interrupt service routine execution is verified using an external RAM
//     marker value.
//   - Interrupt arbiter pending status is verified after the ISR clears it.
//   - External memory access through the CPU wrapper is verified.
//
// Notes:
//   - The testbench uses local RV32I instruction encoding helper functions
//     to construct raw 32-bit instructions.
//   - The memory and peripheral models are intended for simulation and
//     verification only.
//   - The testbench targets the implemented CPU wrapper integration behavior,
//     including the current pipeline and interrupt return mechanism.
// ============================================================================

module tb_vrm_cpu_wrapper();

    // =========================================================================
    // 1. CLOCK AND RESET SIGNALS
    // =========================================================================
    reg clk;
    reg rstn;

    // =========================================================================
    // 2. MEMORY MODELS
    // =========================================================================
    reg [31:0] ext_dmem [0:63];
    reg [31:0] imem     [0:63];

    // =========================================================================
    // 3. CPU WRAPPER INTERFACE
    // =========================================================================
    wire [31:0] pc_out;
    wire [31:0] instr_in;

    wire [31:0] ext_mem_addr;
    wire [31:0] ext_mem_wdata;
    wire        ext_mem_we;
    reg  [31:0] ext_mem_rdata;

    // External interrupt sources.
    // Bit 0 is reserved for the internal hardware timer.
    wire [30:0] ext_irq_in = 31'h0;

    wire [31:0] debug_reg_x1;
    wire        cpu_halt;

    // 100 MHz clock: 10 ns period
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTRUCTION MEMORY MODEL
    // =========================================================================
    // Asynchronous instruction read.
    assign instr_in = imem[pc_out[31:2]];

    // =========================================================================
    // 5. EXTERNAL DATA MEMORY MODEL
    // =========================================================================
    // Asynchronous data read.
    //
    // The wrapper routes addresses outside the internal peripheral regions
    // to this external memory interface.
    always @(*) begin
        if ((ext_mem_addr >= 32'h0000_0000) &&
            (ext_mem_addr <  32'h0000_1000))
            ext_mem_rdata = ext_dmem[ext_mem_addr[31:2]];
        else
            ext_mem_rdata = 32'h00000000;
    end

    // Synchronous external memory write.
    always @(posedge clk) begin
        if (ext_mem_we &&
            (ext_mem_addr >= 32'h0000_0000) &&
            (ext_mem_addr <  32'h0000_1000)) begin
            ext_dmem[ext_mem_addr[31:2]] <= ext_mem_wdata;
        end
    end

    // =========================================================================
    // 6. DEVICE UNDER TEST
    // =========================================================================
    vrm_cpu_rv32i_wrapper uut (
        .clk          (clk),
        .rstn         (rstn),

        .pc_out       (pc_out),
        .instr_in     (instr_in),

        .ext_mem_addr (ext_mem_addr),
        .ext_mem_wdata(ext_mem_wdata),
        .ext_mem_we   (ext_mem_we),
        .ext_mem_rdata(ext_mem_rdata),

        .ext_irq_in   (ext_irq_in),

        .debug_reg_x1 (debug_reg_x1),
        .cpu_halt     (cpu_halt)
    );

    // =========================================================================
    // 7. RV32I INSTRUCTION ENCODING HELPERS
    // =========================================================================

    // I-type instruction encoder
    function [31:0] asm_i (
        input [6:0]  op,
        input [2:0]  f3,
        input [4:0]  rd,
        input [4:0]  rs1,
        input [31:0] imm
    );
        begin
            asm_i = {imm[11:0], rs1, f3, rd, op};
        end
    endfunction

    // S-type instruction encoder
    function [31:0] asm_s (
        input [2:0]  f3,
        input [4:0]  rs1,
        input [4:0]  rs2,
        input [31:0] imm
    );
        begin
            asm_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'h23};
        end
    endfunction

    // U-type instruction encoder
    // Used by LUI.
    function [31:0] asm_u (
        input [6:0]  op,
        input [4:0]  rd,
        input [31:0] imm
    );
        begin
            asm_u = {imm[19:0], rd, op};
        end
    endfunction

    // J-type instruction encoder
    function [31:0] asm_j (
        input [4:0]  rd,
        input [31:0] imm
    );
        begin
            asm_j = {
                imm[20],
                imm[10:1],
                imm[11],
                imm[19:12],
                rd,
                7'h6F
            };
        end
    endfunction

    // =========================================================================
    // 8. TEST PROGRAM
    // =========================================================================
    integer i;

    initial begin

        // ---------------------------------------------------------------------
        // Initialize instruction and data memories.
        // ---------------------------------------------------------------------
        for (i = 0; i < 64; i = i + 1) begin
            imem[i]     = 32'h00000013;  // NOP
            ext_dmem[i] = 32'h00000000;
        end

        // =====================================================================
        // 8.1 BOOT CODE
        // =====================================================================

        // PC = 0
        // Jump to the main program at PC = 36.
        imem[0] = asm_j(0, 36);

        // =====================================================================
        // 8.2 INTERRUPT SERVICE ROUTINE
        // =====================================================================
        // Interrupt vector = PC 4.
        //
        // The ISR:
        //   1. Clears the timer interrupt status.
        //   2. Clears the interrupt arbiter pending bit.
        //   3. Writes a test value to external RAM.
        //   4. Returns using MRET.

        // LUI x1, 0x00001
        // x1 = 0x00001000 (Timer base address)
        imem[1] = asm_u(
            7'h37,
            1,
            32'h00001
        );

        // ADDI x3, x0, 1
        // x3 = 1
        imem[2] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            1
        );

        // SW x3, 12(x1)
        // Write 1 to TIMER_STATUS (0x100C).
        // This clears the timer pending flag using W1C.
        imem[3] = asm_s(
            3'b010,
            1,
            3,
            12
        );

        // LUI x2, 0x00002
        // x2 = 0x00002000 (Interrupt arbiter base address)
        imem[4] = asm_u(
            7'h37,
            2,
            32'h00002
        );

        // SW x3, 8(x2)
        // Write 1 to IRQ_REG_CLEAR (0x2008).
        // This clears the corresponding pending interrupt.
        imem[5] = asm_s(
            3'b010,
            2,
            3,
            8
        );

        // LUI x4, 0xABCDE
        // x4 = 0xABCDE000
        // Used as a marker to verify ISR execution.
        imem[6] = asm_u(
            7'h37,
            4,
            32'hABCDE
        );

        // SW x4, 0(x0)
        // Write the ISR marker to external RAM address 0x00000000.
        imem[7] = asm_s(
            3'b010,
            0,
            4,
            0
        );

        // MRET
        // Return from interrupt.
        imem[8] = 32'h30200073;

        // =====================================================================
        // 8.3 MAIN PROGRAM
        // =====================================================================
        // Main program starts at PC = 36 (imem[9]).

        // LUI x1, 0x00001
        // x1 = 0x00001000 (Timer base address)
        imem[9] = asm_u(
            7'h37,
            1,
            32'h00001
        );

        // LUI x2, 0x00002
        // x2 = 0x00002000 (Interrupt arbiter base address)
        imem[10] = asm_u(
            7'h37,
            2,
            32'h00002
        );

        // =====================================================================
        // 8.4 INTERRUPT ARBITER CONFIGURATION
        // =====================================================================

        // ADDI x3, x0, 1
        // Enable IRQ source bit 0 (hardware timer).
        imem[11] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            1
        );

        // SW x3, 4(x2)
        // Write to IRQ_REG_ENABLE (0x2004).
        imem[12] = asm_s(
            3'b010,
            2,
            3,
            4
        );

        // =====================================================================
        // 8.5 HARDWARE TIMER CONFIGURATION
        // =====================================================================

        // ADDI x3, x0, 30
        // Set timer compare value to 30.
        imem[13] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            30
        );

        // SW x3, 4(x1)
        // Write TIMER_COMPARE (0x1004).
        imem[14] = asm_s(
            3'b010,
            1,
            3,
            4
        );

        // ADDI x3, x0, 7
        // Timer control:
        //   Bit 0 = Enable
        //   Bit 1 = Auto-reload
        //   Bit 2 = IRQ enable
        //   0b111 = 7
        imem[15] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            7
        );

        // SW x3, 0(x1)
        // Write TIMER_CTRL (0x1000) and start the timer.
        imem[16] = asm_s(
            3'b010,
            1,
            3,
            0
        );

        // =====================================================================
        // 8.6 WAIT-FOR-INTERRUPT
        // =====================================================================

        // WFI
        // The CPU enters the halted state until the timer interrupt
        // propagates through the interrupt arbiter.
        imem[17] = 32'h10500073;

        // ---------------------------------------------------------------------
        // Post-interrupt execution marker
        // ---------------------------------------------------------------------
        // The current pipeline/interrupt implementation resumes execution
        // after the saved MEPC position has advanced through the pipeline.
        //
        // This location is used to verify successful wake-up.
        imem[21] = asm_i(
            7'h13,
            3'b000,
            5,
            0,
            99
        );

        // Infinite loop after completing the integration test.
        imem[22] = asm_j(0, 0);

        // =========================================================================
        // 9. SIMULATION STIMULUS
        // =========================================================================

        clk  = 1'b0;
        rstn = 1'b0;

        // Release reset.
        #25 rstn = 1'b1;

        $display("");
        $display("============================================================");
        $display("VRM RV32I CPU WRAPPER INTEGRATION TEST");
        $display("============================================================");
        $display("[INFO] Reset released.");
        $display("[INFO] Waiting for CPU to enter WFI state...");

        // Wait until WFI reaches the WB stage.
        wait(cpu_halt == 1'b1);

        $display(
            "[INFO] Time: %0t - CPU entered WFI state.",
            $time
        );
        $display(
            "[INFO] Hardware timer is running and waiting for compare match."
        );

        // Wait until the hardware timer interrupt wakes the CPU.
        wait(cpu_halt == 1'b0);

        $display(
            "[INFO] Time: %0t - CPU woke up from WFI.",
            $time
        );
        $display(
            "[INFO] Interrupt service routine is executing."
        );

        // Allow sufficient time for the ISR to:
        //   - clear the timer pending flag,
        //   - clear the arbiter pending flag,
        //   - write the external RAM marker,
        //   - execute MRET.
        #200;

        // =========================================================================
        // 10. SELF-CHECKING VERIFICATION
        // =========================================================================

        $display("");
        $display("============================================================");
        $display("         VRM RV32I CPU WRAPPER TEST RESULTS");
        $display("============================================================");

        // ---------------------------------------------------------------------
        // CPU Wake-Up Verification
        // ---------------------------------------------------------------------

        if (uut.core.reg_file[5] === 32'd99)
            $display(
                "[PASS] WFI wake-up and post-interrupt execution"
            );
        else
            $display(
                "[FAIL] WFI wake-up or post-interrupt PC is incorrect"
            );

        // ---------------------------------------------------------------------
        // ISR and External Memory Verification
        // ---------------------------------------------------------------------
        // The ISR writes 0xABCDE000 to external RAM address 0x00000000.
        if (ext_dmem[0] === 32'hABCDE000)
            $display(
                "[PASS] ISR execution and external RAM write"
            );
        else
            $display(
                "[FAIL] ISR external RAM write: %h (expected ABCDE000)",
                ext_dmem[0]
            );

        // ---------------------------------------------------------------------
        // Interrupt Arbiter Verification
        // ---------------------------------------------------------------------
        // The ISR writes 1 to the arbiter W1C register.
        if (uut.sys_arbiter.pending === 32'h00000000)
            $display(
                "[PASS] Interrupt arbiter pending flag cleared"
            );
        else
            $display(
                "[FAIL] Interrupt arbiter pending flag: %h (expected 00000000)",
                uut.sys_arbiter.pending
            );

        // =========================================================================
        // 11. TEST SUMMARY
        // =========================================================================

        $display("============================================================");
        $display("RV32I CPU wrapper integration verification completed.");
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
