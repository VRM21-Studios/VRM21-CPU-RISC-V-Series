`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_cpu_wrapper
// Description : RV32I CPU wrapper integration verification using simulated
//               instruction memory, external data memory, hardware timer,
//               and interrupt arbiter interfaces.
//
// Features:
//   - RV32I CPU wrapper integration verification
//   - Instruction memory model
//   - External data memory model
//   - Hardware timer configuration and interrupt generation
//   - Interrupt arbiter configuration and pending-bit clearing
//   - WFI and MRET interrupt handling verification
//   - External memory access from the interrupt service routine (ISR)
//   - Post-interrupt instruction execution verification
//   - Self-checking verification of CPU, interrupt, and memory behavior
//
// Test Flow:
//   1. Initialize the instruction and external data memory models.
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
// SoC Address Map (vrm_soc_map_rv32i.vh):
//   TIMER_BASE_ADDR = 32'h4000_0000
//   IRQ_BASE_ADDR   = 32'h4000_1000
//   RAM_BASE_ADDR   = 32'h1000_0000
//   Testbench RAM window: 0x1000_0000 .. 0x1001_0000
//
// Interrupt Sources:
//   - External interrupt input is held inactive during this test.
//   - Interrupt source bit 0 is reserved for the internal hardware timer.
//   - The hardware timer interrupt is routed through the interrupt arbiter.
//
// Verification:
//   - CPU wake-up from WFI is verified through post-interrupt execution.
//   - ISR execution is verified using an external RAM marker value.
//   - Interrupt arbiter pending status is verified after the ISR clears it.
//   - External memory access through the CPU wrapper is verified.
//
// Notes:
//   - The testbench uses local RV32I instruction-encoding helper functions
//     to construct raw 32-bit instructions.
//   - The memory and peripheral models are intended for simulation and
//     verification only.
//   - The testbench targets the implemented CPU wrapper integration behavior,
//     including the current pipeline and interrupt-return mechanism.
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

    // 100 MHz clock: 10 ns period.
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTRUCTION MEMORY MODEL
    // =========================================================================
    // Asynchronous instruction read.
    assign instr_in = imem[pc_out[31:2]];

    // =========================================================================
    // 5. EXTERNAL DATA MEMORY MODEL
    // =========================================================================
    // System RAM address range defined by vrm_soc_map_rv32i.vh:
    // 0x1000_0000 .. 0x1001_0000.
    // The testbench implements a smaller 64-word memory window for simulation.
    always @(*) begin
        if ((ext_mem_addr >= 32'h1000_0000) &&
            (ext_mem_addr <  32'h1001_0000))
            ext_mem_rdata = ext_dmem[ext_mem_addr[7:2]];
        else
            ext_mem_rdata = 32'h00000000;
    end

    // Synchronous external memory write.
    always @(posedge clk) begin
        if (ext_mem_we &&
            (ext_mem_addr >= 32'h1000_0000) &&
            (ext_mem_addr <  32'h1001_0000)) begin
            ext_dmem[ext_mem_addr[7:2]] <= ext_mem_wdata;
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
    // 7. RV32I INSTRUCTION-ENCODING HELPERS
    // =========================================================================

    // I-type instruction encoder.
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

    // S-type instruction encoder.
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

    // U-type instruction encoder.
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

    // J-type instruction encoder.
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

        // PC = 0.
        // Jump to the main program at PC = 40 (imem[10]).
        // Instructions imem[1] through imem[9] contain the ISR and are
        // skipped by this JAL instruction.
        imem[0] = asm_j(0, 40);

        // =====================================================================
        // 8.2 INTERRUPT SERVICE ROUTINE
        // =====================================================================
        // Interrupt vector = PC 4 (imem[1]).
        //
        // The ISR performs the following operations:
        //   1. Load the timer, RAM, and interrupt arbiter base addresses.
        //   2. Write an execution marker to external RAM.
        //   3. Clear the timer interrupt status using W1C.
        //   4. Clear the interrupt arbiter pending bit using W1C.
        //   5. Return from the interrupt using MRET.

        // LUI x1, 0x40000.
        // x1 = 0x4000_0000 (TIMER_BASE_ADDR).
        imem[1] = asm_u(
            7'h37,
            1,
            32'h40000
        );

        // LUI x2, 0x10000.
        // x2 = 0x1000_0000 (RAM_BASE_ADDR), used for the ISR marker write.
        imem[2] = asm_u(
            7'h37,
            2,
            32'h10000
        );

        // LUI x4, 0xABCDE.
        // x4 = 0xABCDE000 (ISR execution marker).
        imem[3] = asm_u(
            7'h37,
            4,
            32'hABCDE
        );

        // SW x4, 0(x2).
        // Write 0xABCDE000 to external RAM at 0x1000_0000.
        imem[4] = asm_s(
            3'b010,
            2,
            4,
            0
        );

        // ADDI x3, x0, 1.
        // x3 = 1, used as the W1C clear value.
        imem[5] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            1
        );

        // SW x3, 12(x1).
        // Write 1 to TIMER_STATUS (0x4000_000C) to clear the timer
        // interrupt pending status using W1C.
        imem[6] = asm_s(
            3'b010,
            1,
            3,
            12
        );

        // LUI x2, 0x40001.
        // x2 = 0x4000_1000 (IRQ_BASE_ADDR).
        // The register is reused for the interrupt arbiter access.
        imem[7] = asm_u(
            7'h37,
            2,
            32'h40001
        );

        // SW x3, 8(x2).
        // Write 1 to IRQ_REG_CLEAR (0x4000_1008) to clear the interrupt
        // arbiter pending bit using W1C.
        imem[8] = asm_s(
            3'b010,
            2,
            3,
            8
        );

        // MRET.
        // Return from the interrupt handler.
        imem[9] = 32'h30200073;

        // =====================================================================
        // 8.3 MAIN PROGRAM
        // =====================================================================
        // Main program starts at PC = 40 (imem[10]).

        // LUI x1, 0x40000.
        // x1 = 0x4000_0000 (TIMER_BASE_ADDR).
        imem[10] = asm_u(
            7'h37,
            1,
            32'h40000
        );

        // LUI x2, 0x40001.
        // x2 = 0x4000_1000 (IRQ_BASE_ADDR).
        imem[11] = asm_u(
            7'h37,
            2,
            32'h40001
        );

        // =====================================================================
        // 8.4 INTERRUPT ARBITER CONFIGURATION
        // =====================================================================

        // ADDI x3, x0, 1.
        // Enable interrupt source bit 0 (hardware timer).
        imem[12] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            1
        );

        // SW x3, 4(x2).
        // Write to IRQ_REG_ENABLE (0x4000_1004).
        imem[13] = asm_s(
            3'b010,
            2,
            3,
            4
        );

        // =====================================================================
        // 8.5 HARDWARE TIMER CONFIGURATION
        // =====================================================================

        // ADDI x3, x0, 30.
        // Set the timer compare value to 30.
        imem[14] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            30
        );

        // SW x3, 4(x1).
        // Write the timer compare value to TIMER_COMPARE (0x4000_0004).
        imem[15] = asm_s(
            3'b010,
            1,
            3,
            4
        );

        // ADDI x3, x0, 7.
        // Timer control configuration:
        //   Bit 0 = Enable
        //   Bit 1 = Auto-reload
        //   Bit 2 = Interrupt enable
        //   0b111 = 7
        imem[16] = asm_i(
            7'h13,
            3'b000,
            3,
            0,
            7
        );

        // SW x3, 0(x1).
        // Write TIMER_CTRL (0x4000_0000) and start the timer.
        imem[17] = asm_s(
            3'b010,
            1,
            3,
            0
        );

        // =====================================================================
        // 8.6 WAIT-FOR-INTERRUPT
        // =====================================================================

        // WFI (PC = 72).
        // The CPU enters the halted state until the timer interrupt propagates
        // through the interrupt arbiter.
        imem[18] = 32'h10500073;

        // ---------------------------------------------------------------------
        // Post-interrupt execution marker.
        // ---------------------------------------------------------------------
        // WFI is located at imem[18] (PC = 72). When WFI reaches the WB stage,
        // the PC will have advanced by 16 bytes to PC = 88 (imem[22]).
        // After MRET, execution resumes at that location and executes the
        // post-interrupt marker instruction.
        imem[22] = asm_i(
            7'h13,
            3'b000,
            5,
            0,
            99
        );

        // Infinite loop after completing the integration test.
        imem[23] = asm_j(0, 0);

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
        //   - clear the interrupt arbiter pending flag,
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
                "[FAIL] WFI wake-up or post-interrupt PC is incorrect (x5 = %h)",
                uut.core.reg_file[5]
            );

        // ---------------------------------------------------------------------
        // ISR and External Memory Verification
        // ---------------------------------------------------------------------
        // The ISR writes 0xABCDE000 to external RAM at 0x1000_0000,
        // which maps to ext_dmem[0] in this testbench memory model.
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
        // The ISR writes 1 to the arbiter W1C clear register.
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

    // Watchdog timer: safety mechanism to prevent simulation hang.
    initial begin
        #500000;
        $display("[WATCHDOG] Simulation timeout - forced stop");
        $finish;
    end

endmodule
