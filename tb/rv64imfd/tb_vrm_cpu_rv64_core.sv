`timescale 1ns / 1ps

// ============================================================================
// STRESS TESTBENCH: VRM_CPU_RV64_CORE
// Description:
//   Comprehensive RV64IMFD stress test covering:
//     - RV64I ALU operations
//     - RV64M multiplication and division
//     - 64-bit load/store operations
//     - Conditional branch and loop execution
//     - Double-precision floating-point operations
//     - WFI / CPU halt behavior
//
// FPU verification uses FLD directly from the data memory to avoid depending
// on integer-to-floating-point conversion instructions during this test.
// ============================================================================

module tb_vrm_cpu_rv64_core;

    // =========================================================================
    // 1. SIGNAL DECLARATIONS
    // =========================================================================
    reg         clk;
    reg         rstn;
    reg         irq;

    // Instruction interface
    wire [63:0] pc_out;
    reg  [31:0] instr_in;

    // Data memory interface
    wire [63:0] mem_addr;
    wire [63:0] mem_wdata;
    wire        mem_we;
    reg  [63:0] mem_rdata;
    reg         mem_busy;
    wire [7:0]  mem_wstrb;

    // Debug / CPU status
    wire [63:0] debug_reg_x1;
    wire        cpu_halt;


    // =========================================================================
    // 2. DEVICE UNDER TEST
    // =========================================================================
    vrm_cpu_rv64_core dut (
        .clk        (clk),
        .rstn       (rstn),
        .irq        (irq),
        .pc_out     (pc_out),
        .instr_in   (instr_in),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_we     (mem_we),
        .mem_rdata  (mem_rdata),
        .mem_busy   (mem_busy),
        .mem_wstrb  (mem_wstrb),
        .debug_reg_x1(debug_reg_x1),
        .cpu_halt   (cpu_halt)
    );


    // =========================================================================
    // 3. MEMORY MODELS
    // =========================================================================

    // -------------------------------------------------------------------------
    // Instruction Memory
    // -------------------------------------------------------------------------
    reg [31:0] imem [0:1023];

    // CPU reset PC starts at 0x4000.
    // Convert byte address to instruction-memory word index.
    wire [63:0] imem_index = (pc_out - 64'h4000) >> 2;

    always @(*) begin
        if (pc_out >= 64'h4000 && imem_index < 1024)
            instr_in = imem[imem_index];
        else
            instr_in = 32'h00000013; // NOP
    end


    // -------------------------------------------------------------------------
    // Data Memory
    // -------------------------------------------------------------------------
    // Simple byte-addressable little-endian memory model.
    reg [7:0] dmem [0:8191];

    // Limit the simulated address space to 8 KB.
    wire [63:0] dmem_index = mem_addr & 64'h1FFF;

    // Synchronous write operation with byte-enable support.
    always @(posedge clk) begin
        if (mem_we && !mem_busy) begin
            if (mem_wstrb[0]) dmem[dmem_index + 0] <= mem_wdata[7:0];
            if (mem_wstrb[1]) dmem[dmem_index + 1] <= mem_wdata[15:8];
            if (mem_wstrb[2]) dmem[dmem_index + 2] <= mem_wdata[23:16];
            if (mem_wstrb[3]) dmem[dmem_index + 3] <= mem_wdata[31:24];
            if (mem_wstrb[4]) dmem[dmem_index + 4] <= mem_wdata[39:32];
            if (mem_wstrb[5]) dmem[dmem_index + 5] <= mem_wdata[47:40];
            if (mem_wstrb[6]) dmem[dmem_index + 6] <= mem_wdata[55:48];
            if (mem_wstrb[7]) dmem[dmem_index + 7] <= mem_wdata[63:56];
        end
    end

    // Combinational 64-bit little-endian read.
    always @(*) begin
        mem_rdata = {
            dmem[dmem_index + 7],
            dmem[dmem_index + 6],
            dmem[dmem_index + 5],
            dmem[dmem_index + 4],
            dmem[dmem_index + 3],
            dmem[dmem_index + 2],
            dmem[dmem_index + 1],
            dmem[dmem_index + 0]
        };
    end


    // =========================================================================
    // 4. CLOCK GENERATION
    // =========================================================================
    // 100 MHz clock: 10 ns period.
    always #5 clk = ~clk;


    // =========================================================================
    // 5. MINIMAL RV64 MACRO ASSEMBLER
    // =========================================================================
    // These helper functions generate raw 32-bit RISC-V instructions directly
    // inside the testbench. They are intended only for simulation stimulus.

    integer prog_idx = 0;

    // Append one instruction to instruction memory.
    task emit(input [31:0] inst);
    begin
        imem[prog_idx] = inst;
        prog_idx = prog_idx + 1;
    end
    endtask


    // -------------------------------------------------------------------------
    // R-Type Instruction Encoder
    // -------------------------------------------------------------------------
    function [31:0] rv_r(
        input [6:0] f7,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] f3,
        input [4:0] rd,
        input [6:0] op
    );
        rv_r = {f7, rs2, rs1, f3, rd, op};
    endfunction


    // -------------------------------------------------------------------------
    // I-Type Instruction Encoder
    // -------------------------------------------------------------------------
    function [31:0] rv_i(
        input [31:0] imm,
        input [4:0] rs1,
        input [2:0] f3,
        input [4:0] rd,
        input [6:0] op
    );
        rv_i = {imm[11:0], rs1, f3, rd, op};
    endfunction


    // -------------------------------------------------------------------------
    // S-Type Instruction Encoder
    // -------------------------------------------------------------------------
    function [31:0] rv_s(
        input [31:0] imm,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] f3,
        input [6:0] op
    );
        rv_s = {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction


    // -------------------------------------------------------------------------
    // B-Type Instruction Encoder
    // -------------------------------------------------------------------------
    function [31:0] rv_b(
        input [31:0] imm,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] f3,
        input [6:0] op
    );
        rv_b = {
            imm[12],
            imm[10:5],
            rs2,
            rs1,
            f3,
            imm[4:1],
            imm[11],
            op
        };
    endfunction


    // =========================================================================
    // 6. INTEGER INSTRUCTION MACROS
    // =========================================================================

    // Integer immediate arithmetic
    task ADDI(
        input [4:0] rd,
        input [4:0] rs1,
        input [31:0] imm
    );
        emit(rv_i(imm, rs1, 3'b000, rd, 7'h13));
    endtask

    // Integer register-register arithmetic
    task ADD(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        emit(rv_r(7'h00, rs2, rs1, 3'b000, rd, 7'h33));
    endtask

    task SUB(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        emit(rv_r(7'h20, rs2, rs1, 3'b000, rd, 7'h33));
    endtask

    // Logical left shift immediate
    task SLLI(
        input [4:0] rd,
        input [4:0] rs1,
        input [5:0] shamt
    );
        emit(rv_i({6'b0, shamt}, rs1, 3'b001, rd, 7'h13));
    endtask


    // =========================================================================
    // 7. MEMORY INSTRUCTION MACROS
    // =========================================================================

    // 64-bit integer load/store
    task LD(
        input [4:0] rd,
        input [4:0] rs1,
        input [31:0] imm
    );
        emit(rv_i(imm, rs1, 3'b011, rd, 7'h03));
    endtask

    task SD(
        input [4:0] rs2,
        input [4:0] rs1,
        input [31:0] imm
    );
        emit(rv_s(imm, rs2, rs1, 3'b011, 7'h23));
    endtask


    // =========================================================================
    // 8. BRANCH AND MDU INSTRUCTION MACROS
    // =========================================================================

    // Branch if not equal
    task BNE(
        input [4:0] rs1,
        input [4:0] rs2,
        input [31:0] imm
    );
        emit(rv_b(imm, rs2, rs1, 3'b001, 7'h63));
    endtask

    // RV64M multiply/divide operations
    task MUL(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        emit(rv_r(7'h01, rs2, rs1, 3'b000, rd, 7'h33));
    endtask

    task DIV(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        emit(rv_r(7'h01, rs2, rs1, 3'b100, rd, 7'h33));
    endtask


    // =========================================================================
    // 9. FLOATING-POINT INSTRUCTION MACROS
    // =========================================================================

    // Load double-precision floating-point value from memory.
    task FLD(
        input [4:0] fd,
        input [4:0] rs1,
        input [31:0] imm
    );
        emit(rv_i(imm, rs1, 3'b011, fd, 7'h07));
    endtask

    // Double-precision floating-point addition.
    task FADD_D(
        input [4:0] fd,
        input [4:0] fs1,
        input [4:0] fs2
    );
        emit(rv_r(7'b0000001, fs2, fs1, 3'b000, fd, 7'h53));
    endtask

    // Double-precision floating-point multiplication.
    task FMUL_D(
        input [4:0] fd,
        input [4:0] fs1,
        input [4:0] fs2
    );
        emit(rv_r(7'b0001001, fs2, fs1, 3'b000, fd, 7'h53));
    endtask


    // =========================================================================
    // 10. SYSTEM INSTRUCTION MACRO
    // =========================================================================

    // Wait For Interrupt.
    // The CPU should enter the halt state until an interrupt is received.
    task WFI();
        emit(32'h10500073);
    endtask


    // =========================================================================
    // 11. MAIN SIMULATION
    // =========================================================================

    integer i;

    initial begin

        // ---------------------------------------------------------------------
        // Waveform dump
        // ---------------------------------------------------------------------
        $dumpfile("vrm_cpu_stress.vcd");
        $dumpvars(0, tb_vrm_cpu_rv64_core);


        // ---------------------------------------------------------------------
        // Initialize Data Memory
        // ---------------------------------------------------------------------
        for (i = 0; i < 8192; i = i + 1)
            dmem[i] = 8'h00;


        // ---------------------------------------------------------------------
        // Initialize Instruction Memory with NOPs
        // ---------------------------------------------------------------------
        for (i = 0; i < 1024; i = i + 1)
            imem[i] = 32'h00000013;


        // ---------------------------------------------------------------------
        // Inject Floating-Point Test Data into Data Memory
        // ---------------------------------------------------------------------
        // Address 0x100 = 100.0
        // IEEE-754 double precision:
        //   64'h4059_0000_0000_0000
        dmem[12'h107] = 8'h40;
        dmem[12'h106] = 8'h59;

        // Address 0x108 = 50.0
        // IEEE-754 double precision:
        //   64'h4049_0000_0000_0000
        dmem[12'h10F] = 8'h40;
        dmem[12'h10E] = 8'h49;


        // ---------------------------------------------------------------------
        // Stress-Test Firmware
        // ---------------------------------------------------------------------
        prog_idx = 0;

        // Integer ALU
        ADDI(1, 0, 100);     // x1 = 100
        ADDI(2, 0, 50);      // x2 = 50
        ADD(3, 1, 2);        // x3 = 150
        SUB(4, 1, 2);        // x4 = 50
        SLLI(5, 2, 3);       // x5 = 400

        // Integer multiplication and division
        MUL(6, 1, 2);        // x6 = 5000
        DIV(7, 1, 2);        // x7 = 2

        // Integer memory operations
        SD(6, 0, 12'h000);   // RAM[0x000] = 5000
        SD(7, 0, 12'h008);   // RAM[0x008] = 2
        LD(8, 0, 12'h000);   // x8 = 5000
        LD(9, 0, 12'h008);   // x9 = 2


        // ---------------------------------------------------------------------
        // Floating-Point Test
        // ---------------------------------------------------------------------
        // Load operands directly from memory to avoid depending on FCVT
        // instructions during the basic FPU datapath test.
        FLD(0, 0, 12'h100);  // f0 = 100.0
        FLD(1, 0, 12'h108);  // f1 = 50.0

        FADD_D(2, 0, 1);      // f2 = 100.0 + 50.0 = 150.0
        FMUL_D(3, 0, 1);      // f3 = 100.0 * 50.0 = 5000.0


        // ---------------------------------------------------------------------
        // Branch / Loop Test
        // ---------------------------------------------------------------------
        ADDI(10, 0, 5);
        ADDI(10, 10, -1);
        BNE(10, 0, -4);      // Loop until x10 reaches zero


        // ---------------------------------------------------------------------
        // Halt
        // ---------------------------------------------------------------------
        WFI();


        // ---------------------------------------------------------------------
        // Initial CPU State
        // ---------------------------------------------------------------------
        clk      = 0;
        rstn     = 0;
        irq      = 0;
        mem_busy = 0;

        #20;
        rstn = 1;

        $display("[%0t] RV64IMFD stress test started...", $time);


        // ---------------------------------------------------------------------
        // Wait for CPU Halt or Timeout
        // ---------------------------------------------------------------------
        fork

            begin
                wait(cpu_halt == 1'b1);
                $display("[%0t] CPU HALT reached. Test completed.", $time);
            end

            begin
                #10000;
                $display("[%0t] TIMEOUT! Pipeline may be stalled.", $time);
                $finish;
            end

        join_any


        // Allow final writeback activity to settle.
        #10;


        // =========================================================================
        // 12. TEST RESULTS
        // =========================================================================

        $display("========================================");
        $display("        RV64IMFD STRESS TEST RESULTS");
        $display("========================================");

        // Integer ALU
        $display("[ALU] x3 (ADD)   : %0d \t(Expected: 150)",
                 dut.reg_file[3]);

        $display("[ALU] x4 (SUB)   : %0d \t(Expected: 50)",
                 dut.reg_file[4]);

        $display("[ALU] x5 (SLLI)  : %0d \t(Expected: 400)",
                 dut.reg_file[5]);

        $display("----------------------------------------");

        // Integer MDU
        $display("[MDU] x6 (MUL)   : %0d \t(Expected: 5000)",
                 dut.reg_file[6]);

        $display("[MDU] x7 (DIV)   : %0d \t(Expected: 2)",
                 dut.reg_file[7]);

        $display("----------------------------------------");

        // Memory subsystem
        $display("[MEM] x8 (LD)    : %0d \t(Expected: 5000)",
                 dut.reg_file[8]);

        $display("[MEM] x9 (LD)    : %0d \t(Expected: 2)",
                 dut.reg_file[9]);

        $display("----------------------------------------");

        // Branch / loop
        $display("[BRN] x10 (Loop) : %0d \t(Expected: 0)",
                 dut.reg_file[10]);

        $display("----------------------------------------");

        // Floating-point unit
        $display("[FPU] f2 (FADD.D): %h \t(Expected: 4062C00000000000 = 150.0)",
                 dut.freg_file[2]);

        $display("[FPU] f3 (FMUL.D): %h \t(Expected: 40B3880000000000 = 5000.0)",
                 dut.freg_file[3]);

        $display("========================================");


        // ---------------------------------------------------------------------
        // End Simulation
        // ---------------------------------------------------------------------
        $finish;

    end

endmodule
