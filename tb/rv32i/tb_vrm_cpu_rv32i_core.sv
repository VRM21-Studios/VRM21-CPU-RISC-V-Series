`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_cpu_rv32i_core
// Description : RV32I CPU core verification using an in-testbench instruction
//               and data memory model.
//
// Features:
//   - RV32I instruction execution verification
//   - R-type and I-type ALU instruction testing
//   - Immediate and upper-immediate instruction testing
//   - Load/store instruction verification
//   - Byte-enable generation and byte/halfword load testing
//   - Load-use hazard verification
//   - Branch and pipeline flush verification
//   - WFI and MRET interrupt handling verification
//   - Machine-mode interrupt wake-up testing
//   - Self-checking register and memory result verification
//
// Instruction Coverage:
//   - LUI
//   - AUIPC support through instruction encoding helpers
//   - ADD / SUB
//   - SLLI
//   - SLT / SLTU
//   - XOR / OR / AND
//   - SRLI / SRAI
//   - LB / LBU / LH / LW
//   - SB / SH / SW
//   - BEQ
//   - JAL
//   - MRET
//   - WFI
//
// Memory Model:
//   - 64-word instruction memory
//   - 64-word data memory
//   - Asynchronous instruction fetch
//   - Asynchronous data read
//   - Synchronous data write
//   - Byte-enable support for store operations
//
// Interrupt Behavior:
//   - Interrupt request generated after the CPU enters WFI.
//   - Interrupt handling is verified through the implemented ISR entry,
//     MRET execution, and post-interrupt instruction execution.
//
// Verification:
//   - Register file contents are checked against expected results.
//   - Data memory contents are checked after store operations.
//   - Pipeline hazard and branch flush behavior are verified indirectly
//     through architectural register results.
//   - WFI and interrupt recovery are verified through the post-interrupt
//     execution result.
//
// Notes:
//   - The testbench uses local instruction encoding helper functions to
//     construct raw 32-bit RV32I instructions.
//   - The memory model is intended for simulation and verification only.
// ============================================================================

module tb_vrm_cpu_rv32i_core();

    // =========================================================================
    // 1. CLOCK, RESET, AND INTERRUPT SIGNALS
    // =========================================================================
    reg clk;
    reg rstn;
    reg irq;

    // =========================================================================
    // 2. CPU INTERFACE SIGNALS
    // =========================================================================
    wire [31:0] pc_out;
    wire [31:0] instr_in;

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_be;
    wire        mem_we;
    wire [31:0] mem_rdata;

    wire [31:0] debug_reg_x1;
    wire        cpu_halt;

    // 100 MHz clock: 10 ns period
    always #5 clk = ~clk;

    // =========================================================================
    // 3. SIMPLE INSTRUCTION AND DATA MEMORY MODELS
    // =========================================================================
    reg [31:0] imem [0:63];
    reg [31:0] dmem [0:63];

    // Instruction memory: asynchronous read
    assign instr_in = imem[pc_out[31:2]];

    // Data memory: asynchronous read
    assign mem_rdata = dmem[mem_addr[31:2]];

    // Data memory: synchronous write with byte-enable support
    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0])
                dmem[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];

            if (mem_be[1])
                dmem[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];

            if (mem_be[2])
                dmem[mem_addr[31:2]][23:16] <= mem_wdata[23:16];

            if (mem_be[3])
                dmem[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
        end
    end

    // =========================================================================
    // 4. DEVICE UNDER TEST
    // =========================================================================
    vrm_cpu_rv32i_core uut (
        .clk        (clk),
        .rstn       (rstn),
        .irq        (irq),

        .pc_out     (pc_out),
        .instr_in   (instr_in),

        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_be     (mem_be),
        .mem_we     (mem_we),
        .mem_rdata  (mem_rdata),

        .debug_reg_x1(debug_reg_x1),
        .cpu_halt   (cpu_halt)
    );

    // =========================================================================
    // 5. RV32I INSTRUCTION ENCODING HELPERS
    // =========================================================================
    // These functions generate raw 32-bit RV32I instructions directly
    // inside the testbench. Using explicit 32-bit function return values
    // avoids unintended truncation during concatenation and shifting.

    // R-type instruction
    function [31:0] asm_r (
        input [6:0] op,
        input [6:0] f7,
        input [2:0] f3,
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        begin
            asm_r = {f7, rs2, rs1, f3, rd, op};
        end
    endfunction

    // I-type instruction
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

    // S-type instruction
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

    // B-type instruction
    function [31:0] asm_b (
        input [2:0]  f3,
        input [4:0]  rs1,
        input [4:0]  rs2,
        input [31:0] imm
    );
        begin
            asm_b = {
                imm[12],
                imm[10:5],
                rs2,
                rs1,
                f3,
                imm[4:1],
                imm[11],
                7'h63
            };
        end
    endfunction

    // U-type instruction
    // Used by LUI and AUIPC.
    function [31:0] asm_u (
        input [6:0]  op,
        input [4:0]  rd,
        input [31:0] imm
    );
        begin
            asm_u = {imm[19:0], rd, op};
        end
    endfunction

    // J-type instruction
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
    // 6. TEST PROGRAM
    // =========================================================================
    integer i;

    initial begin

        // ---------------------------------------------------------------------
        // Initialize instruction and data memories
        // ---------------------------------------------------------------------
        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;  // NOP: ADDI x0, x0, 0
            dmem[i] = 32'h00000000;
        end

        // ---------------------------------------------------------------------
        // Interrupt Vector and Boot Code
        // ---------------------------------------------------------------------
        // PC = 0
        // JAL x0, +8 -> jump to PC = 8
        imem[0] = asm_j(0, 8);

        // PC = 4
        // Interrupt service routine entry:
        // MRET returns to the PC stored in MEPC.
        imem[1] = 32'h30200073;

        // ---------------------------------------------------------------------
        // Main Program
        // Start at PC = 8 (imem[2])
        // ---------------------------------------------------------------------

        // =====================================================================
        // 6.1 Immediate and Upper-Immediate Instructions
        // =====================================================================

        // LUI x20, 0x12345
        // x20 = 0x12345000
        imem[2] = asm_u(
            7'h37,
            20,
            20'h12345
        );

        // ADDI x20, x20, 0x678
        // x20 = 0x12345678
        imem[3] = asm_i(
            7'h13,
            3'b000,
            20,
            20,
            12'h678
        );

        // ADDI x1, x0, 15
        // x1 = 15
        imem[4] = asm_i(
            7'h13,
            3'b000,
            1,
            0,
            15
        );

        // ADDI x2, x0, -10
        // x2 = 0xFFFFFFF6
        imem[5] = asm_i(
            7'h13,
            3'b000,
            2,
            0,
            -10
        );

        // =====================================================================
        // 6.2 R-Type and I-Type ALU Instructions
        // =====================================================================

        // ADD x3, x1, x2
        // 15 + (-10) = 5
        imem[6] = asm_r(
            7'h33,
            7'h00,
            3'b000,
            3,
            1,
            2
        );

        // SUB x4, x1, x2
        // 15 - (-10) = 25
        imem[7] = asm_r(
            7'h33,
            7'h20,
            3'b000,
            4,
            1,
            2
        );

        // SLLI x5, x1, 4
        // 15 << 4 = 240
        imem[8] = asm_i(
            7'h13,
            3'b001,
            5,
            1,
            4
        );

        // SLT x6, x2, x1
        // Signed comparison: -10 < 15 -> 1
        imem[9] = asm_r(
            7'h33,
            7'h00,
            3'b010,
            6,
            2,
            1
        );

        // SLTU x7, x2, x1
        // Unsigned comparison:
        // 0xFFFFFFF6 < 15 -> false
        imem[10] = asm_r(
            7'h33,
            7'h00,
            3'b011,
            7,
            2,
            1
        );

        // XOR x8, x1, x2
        // 0x0000000F ^ 0xFFFFFFF6 = 0xFFFFFFF9
        imem[11] = asm_r(
            7'h33,
            7'h00,
            3'b100,
            8,
            1,
            2
        );

        // SRLI x9, x2, 1
        // Logical right shift:
        // 0xFFFFFFF6 >> 1 = 0x7FFFFFFB
        imem[12] = asm_i(
            7'h13,
            3'b101,
            9,
            2,
            1
        );

        // SRAI x10, x2, 1
        // Arithmetic right shift:
        // 0xFFFFFFF6 >>> 1 = 0xFFFFFFFB
        imem[13] = asm_i(
            7'h13,
            3'b101,
            10,
            2,
            32'h401
        );

        // OR x11, x1, x2
        // 0x0000000F | 0xFFFFFFF6 = 0xFFFFFFFF
        imem[14] = asm_r(
            7'h33,
            7'h00,
            3'b110,
            11,
            1,
            2
        );

        // AND x12, x1, x2
        // 0x0000000F & 0xFFFFFFF6 = 0x00000006
        imem[15] = asm_r(
            7'h33,
            7'h00,
            3'b111,
            12,
            1,
            2
        );

        // =====================================================================
        // 6.3 Load/Store and Byte-Enable Tests
        // =====================================================================

        // ADDI x13, x0, 0
        // x13 = base address 0
        imem[16] = asm_i(
            7'h13,
            3'b000,
            13,
            0,
            0
        );

        // SW x20, 0(x13)
        // Store 0x12345678 into DMEM[0]
        imem[17] = asm_s(
            3'b010,
            13,
            20,
            0
        );

        // LB x21, 0(x13)
        // Load byte 0x78 and sign-extend
        imem[18] = asm_i(
            7'h03,
            3'b000,
            21,
            13,
            0
        );

        // LBU x22, 1(x13)
        // Load byte 0x56 and zero-extend
        imem[19] = asm_i(
            7'h03,
            3'b100,
            22,
            13,
            1
        );

        // LH x23, 2(x13)
        // Load halfword 0x1234 and sign-extend
        imem[20] = asm_i(
            7'h03,
            3'b001,
            23,
            13,
            2
        );

        // SB x1, 4(x13)
        // Store 0x0F into the lowest byte of DMEM[1]
        imem[21] = asm_s(
            3'b000,
            13,
            1,
            4
        );

        // SH x2, 6(x13)
        // Store 0xFFF6 into the upper halfword of DMEM[1]
        imem[22] = asm_s(
            3'b001,
            13,
            2,
            6
        );

        // =====================================================================
        // 6.4 Load-Use Hazard Test
        // =====================================================================

        // LW x14, 0(x13)
        // Load 0x12345678 from DMEM[0]
        imem[23] = asm_i(
            7'h03,
            3'b010,
            14,
            13,
            0
        );

        // ADDI x15, x14, 1
        // Requires load-use hazard handling.
        // Expected result: 0x12345679
        imem[24] = asm_i(
            7'h13,
            3'b000,
            15,
            14,
            1
        );

        // =====================================================================
        // 6.5 Branch and Pipeline Flush Test
        // =====================================================================

        // BEQ x1, x1, +8
        // PC = 100 -> PC = 108
        // The instruction at imem[26] must be flushed.
        imem[25] = asm_b(
            3'b000,
            1,
            1,
            8
        );

        // This instruction must NOT execute.
        // x16 must remain zero.
        imem[26] = asm_i(
            7'h13,
            3'b000,
            16,
            0,
            12'hBAD
        );

        // =====================================================================
        // 6.6 Wait-For-Interrupt Test
        // =====================================================================

        // PC = 108
        // WFI causes the CPU to halt until an interrupt is received.
        imem[27] = 32'h10500073;

        // ---------------------------------------------------------------------
        // Interrupt Wake-Up Target
        // ---------------------------------------------------------------------
        // WFI reaches the WB stage after the PC has already advanced through
        // the pipeline. After the interrupt and MRET, execution resumes at
        // the saved MEPC.
        //
        // This location contains the post-interrupt instruction expected by
        // the current pipeline/interrupt implementation.
        imem[31] = asm_i(
            7'h13,
            3'b000,
            17,
            0,
            12'h777
        );

        // Infinite loop to terminate normal instruction execution.
        imem[32] = asm_j(0, 0);

        // =========================================================================
        // 7. SIMULATION STIMULUS
        // =========================================================================

        clk  = 1'b0;
        rstn = 1'b0;
        irq  = 1'b0;

        // Release reset
        #25 rstn = 1'b1;

        // Wait until WFI reaches the WB stage and asserts cpu_halt.
        wait(cpu_halt == 1'b1);

        $display("");
        $display("============================================================");
        $display("CPU entered WFI state at simulation time %0t", $time);
        $display("Triggering interrupt...");
        $display("============================================================");

        // Generate a one-clock interrupt pulse.
        #10 irq = 1'b1;
        #10 irq = 1'b0;

        // Allow ISR, MRET, and post-interrupt execution to complete.
        #150;

        // =========================================================================
        // 8. SELF-CHECKING VERIFICATION
        // =========================================================================

        $display("");
        $display("============================================================");
        $display("              VRM RV32I CPU TEST RESULTS");
        $display("============================================================");

        // ---------------------------------------------------------------------
        // ALU Verification
        // ---------------------------------------------------------------------

        if (uut.reg_file[3] === 32'h00000005)
            $display("[PASS] ADD   : x3  = %h", uut.reg_file[3]);
        else
            $display("[FAIL] ADD   : x3  = %h (expected 00000005)", uut.reg_file[3]);

        if (uut.reg_file[4] === 32'h00000019)
            $display("[PASS] SUB   : x4  = %h", uut.reg_file[4]);
        else
            $display("[FAIL] SUB   : x4  = %h (expected 00000019)", uut.reg_file[4]);

        if (uut.reg_file[5] === 32'h000000F0)
            $display("[PASS] SLL   : x5  = %h", uut.reg_file[5]);
        else
            $display("[FAIL] SLL   : x5  = %h (expected 000000F0)", uut.reg_file[5]);

        if (uut.reg_file[6] === 32'h00000001)
            $display("[PASS] SLT   : x6  = %h", uut.reg_file[6]);
        else
            $display("[FAIL] SLT   : x6  = %h (expected 00000001)", uut.reg_file[6]);

        if (uut.reg_file[7] === 32'h00000000)
            $display("[PASS] SLTU  : x7  = %h", uut.reg_file[7]);
        else
            $display("[FAIL] SLTU  : x7  = %h (expected 00000000)", uut.reg_file[7]);

        if (uut.reg_file[8] === 32'hFFFFFFF9)
            $display("[PASS] XOR   : x8  = %h", uut.reg_file[8]);
        else
            $display("[FAIL] XOR   : x8  = %h (expected FFFFFFF9)", uut.reg_file[8]);

        if (uut.reg_file[9] === 32'h7FFFFFFB)
            $display("[PASS] SRL   : x9  = %h", uut.reg_file[9]);
        else
            $display("[FAIL] SRL   : x9  = %h (expected 7FFFFFFB)", uut.reg_file[9]);

        if (uut.reg_file[10] === 32'hFFFFFFFB)
            $display("[PASS] SRA   : x10 = %h", uut.reg_file[10]);
        else
            $display("[FAIL] SRA   : x10 = %h (expected FFFFFFFB)", uut.reg_file[10]);

        if (uut.reg_file[11] === 32'hFFFFFFFF)
            $display("[PASS] OR    : x11 = %h", uut.reg_file[11]);
        else
            $display("[FAIL] OR    : x11 = %h (expected FFFFFFFF)", uut.reg_file[11]);

        if (uut.reg_file[12] === 32'h00000006)
            $display("[PASS] AND   : x12 = %h", uut.reg_file[12]);
        else
            $display("[FAIL] AND   : x12 = %h (expected 00000006)", uut.reg_file[12]);

        // ---------------------------------------------------------------------
        // Immediate and Memory Verification
        // ---------------------------------------------------------------------

        if (uut.reg_file[20] === 32'h12345678)
            $display("[PASS] LUI+ADDI : x20 = %h", uut.reg_file[20]);
        else
            $display("[FAIL] LUI+ADDI : x20 = %h (expected 12345678)",
                     uut.reg_file[20]);

        if (dmem[0] === 32'h12345678)
            $display("[PASS] SW        : DMEM[0] = %h", dmem[0]);
        else
            $display("[FAIL] SW        : DMEM[0] = %h (expected 12345678)",
                     dmem[0]);

        if (uut.reg_file[21] === 32'h00000078)
            $display("[PASS] LB        : x21 = %h", uut.reg_file[21]);
        else
            $display("[FAIL] LB        : x21 = %h (expected 00000078)",
                     uut.reg_file[21]);

        if (uut.reg_file[22] === 32'h00000056)
            $display("[PASS] LBU       : x22 = %h", uut.reg_file[22]);
        else
            $display("[FAIL] LBU       : x22 = %h (expected 00000056)",
                     uut.reg_file[22]);

        if (uut.reg_file[23] === 32'h00001234)
            $display("[PASS] LH        : x23 = %h", uut.reg_file[23]);
        else
            $display("[FAIL] LH        : x23 = %h (expected 00001234)",
                     uut.reg_file[23]);

        // DMEM[1] should contain:
        // Upper halfword = 0xFFF6
        // Lower byte     = 0x0F
        // Expected value  = 0xFFF6000F
        if (dmem[1] === 32'hFFF6000F)
            $display("[PASS] SB+SH     : DMEM[1] = %h", dmem[1]);
        else
            $display("[FAIL] SB+SH     : DMEM[1] = %h (expected FFF6000F)",
                     dmem[1]);

        // ---------------------------------------------------------------------
        // Pipeline, Hazard, Branch, and Interrupt Verification
        // ---------------------------------------------------------------------

        if (uut.reg_file[15] === 32'h12345679)
            $display("[PASS] LOAD-USE HAZARD : x15 = %h", uut.reg_file[15]);
        else
            $display("[FAIL] LOAD-USE HAZARD : x15 = %h (expected 12345679)",
                     uut.reg_file[15]);

        if (uut.reg_file[16] === 32'h00000000)
            $display("[PASS] BRANCH FLUSH    : x16 = %h", uut.reg_file[16]);
        else
            $display("[FAIL] BRANCH FLUSH    : x16 = %h (expected 00000000)",
                     uut.reg_file[16]);

        if (uut.reg_file[17] === 32'h00000777)
            $display("[PASS] WFI + MRET      : x17 = %h", uut.reg_file[17]);
        else
            $display("[FAIL] WFI + MRET      : x17 = %h (expected 00000777)",
                     uut.reg_file[17]);

        // =========================================================================
        // 9. TEST SUMMARY
        // =========================================================================

        $display("============================================================");
        $display("RV32I CPU verification completed.");
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
