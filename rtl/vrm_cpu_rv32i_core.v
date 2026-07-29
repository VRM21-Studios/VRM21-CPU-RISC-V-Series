`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_cpu_rv32i_core
// Description : Pipelined 32-bit RISC-V processor core with RV32I-oriented
//               instruction decode, data forwarding, load-use hazard handling,
//               interrupt support, and WFI-based halt behavior.
//
// Pipeline:
//   IF  -> Instruction Fetch
//   ID  -> Instruction Decode and Register Read
//   EX  -> Execute and Data Forwarding
//   MEM -> Memory Access
//   WB  -> Writeback
//
// Main Features:
// - 32-bit program counter and datapath
// - 32 general-purpose 32-bit registers
// - Register x0 hardwired to zero through read-path logic
// - Five-stage pipelined datapath
// - Load-use hazard detection
// - EX/MEM and MEM/WB data forwarding
// - Conditional branch support
// - JAL and JALR support
// - LUI and AUIPC support
// - Load and store memory interface
// - MRET support
// - WFI-based processor halt behavior
// - Simple interrupt vector handling
// - Debug access to register x1
//
// Instruction Decode:
// - Register-immediate arithmetic and logical operations
// - Register-register arithmetic and logical operations
// - Branch instructions
// - Jumps
// - Loads and stores
// - Upper-immediate instructions
// - System instructions used by the control flow logic
//
// Interrupt Behavior:
// - A rising/high-level interrupt request is accepted when the processor is
//   not already inside an interrupt service routine.
// - The current PC is stored in MEPC.
// - Execution is redirected to the fixed interrupt vector address 0x00000004.
// - MRET restores execution to the stored MEPC value.
//
// Halt / WFI Behavior:
// - The CPU enters the halted state when a WFI instruction reaches the
//   corresponding pipeline stage.
// - An accepted interrupt releases the halt condition and resumes execution.
//
// Memory Interface:
// - Instruction memory is accessed through pc_out and instr_in.
// - Data memory is accessed through mem_addr, mem_wdata, mem_we, and mem_rdata.
// - Data memory reads are assumed to be returned through the pipeline without
//   an explicit ready/valid handshake.
//
// Note:
// This module is an RTL implementation intended for FPGA-oriented development.
// Architectural compliance and complete ISA coverage depend on the currently
// implemented instruction decoder, ALU operations, and system-control logic.
// ============================================================================

module vrm_cpu_rv32i_core (
    input  wire        clk,
    input  wire        rstn,
    input  wire        irq,

    // =========================================================================
    // INSTRUCTION MEMORY INTERFACE
    // =========================================================================

    // Current program counter presented to instruction memory.
    output wire [31:0] pc_out,

    // Instruction word returned by instruction memory.
    input  wire [31:0] instr_in,

    // =========================================================================
    // DATA MEMORY INTERFACE
    // =========================================================================

    // Calculated data memory address.
    output wire [31:0] mem_addr,

    // Data written to memory during a store operation.
    output wire [31:0] mem_wdata,

    // Asserted during a store operation.
    output wire        mem_we,

    // Data returned by the memory subsystem during a load operation.
    input  wire [31:0] mem_rdata,

    // =========================================================================
    // DEBUG AND STATUS OUTPUTS
    // =========================================================================

    // Debug view of general-purpose register x1.
    output wire [31:0] debug_reg_x1,

    // Processor halt indication, primarily associated with WFI behavior.
    output wire        cpu_halt
);

    // =========================================================================
    // 0. GLOBAL SIGNALS AND HAZARD CONTROL
    // =========================================================================

    // Program counter register.
    reg [31:0] pc;

    assign pc_out = pc;

    // -------------------------------------------------------------------------
    // Pipeline control signals
    // -------------------------------------------------------------------------

    // Asserted when the IF and ID stages must be stalled to resolve a
    // load-use data hazard.
    wire stall;

    // Asserted when younger instructions must be removed from the pipeline
    // due to a taken branch, jump, or MRET operation.
    wire flush_ex;

    // -------------------------------------------------------------------------
    // Interrupt and exception-related state
    // -------------------------------------------------------------------------

    // Indicates that the processor is currently handling an interrupt.
    reg in_isr;

    // Machine exception program counter storage.
    reg [31:0] mepc;

    // Accept an interrupt only when the processor is not already inside an ISR.
    wire irq_trigger = (irq === 1'b1) && !in_isr;

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF)
    // =========================================================================

    // -------------------------------------------------------------------------
    // IF/ID Pipeline Register
    // -------------------------------------------------------------------------

    // Program counter associated with the fetched instruction.
    reg [31:0] if_id_pc;

    // Fetched instruction passed to the decode stage.
    reg [31:0] if_id_instr;

    // -------------------------------------------------------------------------
    // Execute-stage control results
    // -------------------------------------------------------------------------

    // Indicates that a branch or jump is taken.
    wire branch_taken_ex;

    // Target program counter generated by the execute stage.
    wire [31:0] target_pc_ex;

    // Indicates that an MRET instruction is currently executing.
    wire is_mret_ex;

    // -------------------------------------------------------------------------
    // Program Counter Update
    // -------------------------------------------------------------------------
    // PC update priority:
    // 1. Interrupt entry
    // 2. MRET return
    // 3. Normal execution while the CPU is not halted
    // 4. Taken branch or jump
    // 5. Sequential PC increment
    // 6. Hold PC during a load-use stall
    always @(posedge clk) begin
        if (!rstn) begin
            pc     <= 32'h0;
            in_isr <= 0;
            mepc   <= 0;
        end else begin

            // ---------------------------------------------------------------
            // Interrupt entry
            // ---------------------------------------------------------------
            // Redirect execution to the fixed interrupt vector.
            if (irq_trigger) begin
                pc <= 32'h00000004;

                // Preserve the current PC in MEPC.
                mepc <= (cpu_halt) ? pc : pc;

                in_isr <= 1;

            // ---------------------------------------------------------------
            // Return from interrupt
            // ---------------------------------------------------------------
            end else if (is_mret_ex) begin
                pc     <= mepc;
                in_isr <= 0;

            // ---------------------------------------------------------------
            // Normal instruction flow
            // ---------------------------------------------------------------
            end else if (!cpu_halt) begin

                if (branch_taken_ex) begin
                    pc <= target_pc_ex;
                end else if (!stall) begin
                    pc <= pc + 4;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // IF/ID Pipeline Register Update
    // -------------------------------------------------------------------------
    // The fetch/decode boundary is cleared when:
    // - Reset is asserted
    // - A branch or jump is taken
    // - An interrupt is accepted
    // - An MRET is executed
    //
    // A RISC-V NOP instruction is inserted during pipeline flush.
    always @(posedge clk) begin

        if (!rstn || flush_ex || irq_trigger || is_mret_ex) begin
            if_id_instr <= 32'h00000013;
            if_id_pc    <= 32'h0;

        end else if (!stall && !cpu_halt) begin
            if_id_instr <= instr_in;
            if_id_pc    <= pc;
        end
    end

    // =========================================================================
    // 2. INSTRUCTION DECODE (ID) AND REGISTER READ
    // =========================================================================

    // -------------------------------------------------------------------------
    // Instruction Fields
    // -------------------------------------------------------------------------

    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1    = if_id_instr[19:15];
    wire [4:0] id_rs2    = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    // -------------------------------------------------------------------------
    // Immediate Generation
    // -------------------------------------------------------------------------

    // I-type immediate.
    wire [31:0] id_imm_i =
        {{20{if_id_instr[31]}}, if_id_instr[31:20]};

    // S-type immediate.
    wire [31:0] id_imm_s =
        {{20{if_id_instr[31]}},
         if_id_instr[31:25],
         if_id_instr[11:7]};

    // B-type branch immediate.
    wire [31:0] id_imm_b =
        {{19{if_id_instr[31]}},
         if_id_instr[31],
         if_id_instr[7],
         if_id_instr[30:25],
         if_id_instr[11:8],
         1'b0};

    // U-type immediate.
    wire [31:0] id_imm_u =
        {if_id_instr[31:12], 12'h0};

    // J-type jump immediate.
    wire [31:0] id_imm_j =
        {{11{if_id_instr[31]}},
         if_id_instr[31],
         if_id_instr[19:12],
         if_id_instr[20],
         if_id_instr[30:21],
         1'b0};

    // -------------------------------------------------------------------------
    // Register File
    // -------------------------------------------------------------------------

    // 32 general-purpose registers, each 32 bits wide.
    reg [31:0] reg_file [0:31];

    integer i;

    // Initialize register file contents for deterministic simulation startup.
    initial begin
        for (i = 0; i < 32; i = i + 1)
            reg_file[i] = 0;
    end

    // -------------------------------------------------------------------------
    // Register Read and Writeback Forwarding
    // -------------------------------------------------------------------------
    // Register x0 is always returned as zero.
    //
    // When a register value is simultaneously being written back from the
    // MEM/WB stage, the writeback value is forwarded directly to the decode
    // stage to avoid using stale register-file contents.
    wire [31:0] rf_read1 =
        (id_rs1 == 0) ? 32'b0 :
        (mem_wb_reg_we && mem_wb_rd == id_rs1) ? wb_data :
        reg_file[id_rs1];

    wire [31:0] rf_read2 =
        (id_rs2 == 0) ? 32'b0 :
        (mem_wb_reg_we && mem_wb_rd == id_rs2) ? wb_data :
        reg_file[id_rs2];

    // -------------------------------------------------------------------------
    // Control Decoder
    // -------------------------------------------------------------------------

    reg [3:0] id_alu_ctrl;

    reg id_reg_we;
    reg id_mem_we;
    reg id_mem_re;

    reg id_is_branch;
    reg id_is_jump;
    reg id_is_jalr;
    reg id_is_auipc;
    reg id_is_lui;

    // Detect MRET.
    wire id_is_mret =
        (id_opcode == 7'h73 && if_id_instr == 32'h30200073);

    // Detect WFI-related system instructions.
    wire id_is_wfi =
        (id_opcode == 7'h73 &&
        (if_id_instr == 32'h10500073 || if_id_instr == 32'h00100073));

    // -------------------------------------------------------------------------
    // Instruction Decode Logic
    // -------------------------------------------------------------------------

    always @(*) begin

        // Default control values.
        id_reg_we     = 0;
        id_mem_we     = 0;
        id_mem_re     = 0;

        id_is_branch  = 0;
        id_is_jump    = 0;
        id_is_jalr    = 0;
        id_is_auipc   = 0;
        id_is_lui     = 0;

        id_alu_ctrl   = 4'b0000;

        case (id_opcode)

            // ---------------------------------------------------------------
            // LUI
            // ---------------------------------------------------------------
            7'h37: begin
                id_is_lui = 1;
                id_reg_we = 1;
            end

            // ---------------------------------------------------------------
            // AUIPC
            // ---------------------------------------------------------------
            7'h17: begin
                id_is_auipc = 1;
                id_reg_we   = 1;
            end

            // ---------------------------------------------------------------
            // JAL
            // ---------------------------------------------------------------
            7'h6F: begin
                id_is_jump = 1;
                id_reg_we  = 1;
            end

            // ---------------------------------------------------------------
            // JALR
            // ---------------------------------------------------------------
            7'h67: begin
                id_is_jump = 1;
                id_is_jalr = 1;
                id_reg_we  = 1;
            end

            // ---------------------------------------------------------------
            // Conditional Branch
            // ---------------------------------------------------------------
            7'h63: begin
                id_is_branch = 1;
            end

            // ---------------------------------------------------------------
            // Load
            // ---------------------------------------------------------------
            7'h03: begin
                id_mem_re    = 1;
                id_reg_we    = 1;
                id_alu_ctrl  = 4'b0000;
            end

            // ---------------------------------------------------------------
            // Store
            // ---------------------------------------------------------------
            7'h23: begin
                id_mem_we   = 1;
                id_alu_ctrl = 4'b0000;
            end

            // ---------------------------------------------------------------
            // OP-IMM
            // ---------------------------------------------------------------
            7'h13: begin
                id_reg_we = 1;

                case (id_funct3)
                    3'b000: id_alu_ctrl = 4'b0000; // ADDI
                    3'b010: id_alu_ctrl = 4'b0011; // SLTI
                    3'b100: id_alu_ctrl = 4'b0100; // XORI
                    3'b110: id_alu_ctrl = 4'b0110; // ORI
                    3'b111: id_alu_ctrl = 4'b0111; // ANDI
                    3'b001: id_alu_ctrl = 4'b0010; // SLLI
                    3'b101: id_alu_ctrl =
                        (id_funct7[5]) ? 4'b1000 : 4'b0101; // SRAI / SRLI
                    default: id_alu_ctrl = 4'b0000;
                endcase
            end

            // ---------------------------------------------------------------
            // OP
            // ---------------------------------------------------------------
            7'h33: begin
                id_reg_we = 1;

                case (id_funct3)

                    3'b000: begin
                        if (id_funct7 == 7'b0100000)
                            id_alu_ctrl = 4'b0001; // SUB
                        else if (id_funct7 == 7'b0000001)
                            id_alu_ctrl = 4'b1001; // M-extension operation code
                        else
                            id_alu_ctrl = 4'b0000; // ADD
                    end

                    3'b001: id_alu_ctrl = 4'b0010; // SLL
                    3'b010: id_alu_ctrl = 4'b0011; // SLT
                    3'b100: id_alu_ctrl = 4'b0100; // XOR

                    3'b101: id_alu_ctrl =
                        (id_funct7[5]) ? 4'b1000 : 4'b0101; // SRA / SRL

                    3'b110: id_alu_ctrl = 4'b0110; // OR
                    3'b111: id_alu_ctrl = 4'b0111; // AND

                    default: id_alu_ctrl = 4'b0000;
                endcase
            end

        endcase
    end

    // -------------------------------------------------------------------------
    // ALU Operand B Selection
    // -------------------------------------------------------------------------
    // Register-register operations and branches use rs2.
    // Store operations use the S-type immediate.
    // Other immediate-based operations use the I-type immediate.
    wire [31:0] id_alu_op2 =
        (id_opcode == 7'h33 || id_is_branch) ? rf_read2 :
        (id_opcode == 7'h23) ? id_imm_s :
        id_imm_i;

    // =========================================================================
    // ID/EX PIPELINE REGISTER
    // =========================================================================

    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rdata1;
    reg [31:0] id_ex_rdata2;
    reg [31:0] id_ex_imm_b;
    reg [31:0] id_ex_imm_j;
    reg [31:0] id_ex_imm_u;
    reg [31:0] id_ex_alu_op2;

    reg [4:0] id_ex_rs1;
    reg [4:0] id_ex_rs2;
    reg [4:0] id_ex_rd;

    reg [3:0] id_ex_alu_ctrl;
    reg [2:0] id_ex_funct3;
    reg [6:0] id_ex_opcode;

    reg id_ex_reg_we;
    reg id_ex_mem_we;
    reg id_ex_mem_re;

    reg id_ex_is_wfi;
    reg id_ex_is_branch;
    reg id_ex_is_jump;
    reg id_ex_is_jalr;
    reg id_ex_is_auipc;
    reg id_ex_is_lui;
    reg id_ex_is_mret;

    // -------------------------------------------------------------------------
    // ID/EX Pipeline Update
    // -------------------------------------------------------------------------
    // The ID/EX stage is cleared when a hazard, branch flush, or interrupt
    // requires the current instruction to be discarded.
    always @(posedge clk) begin

        if (!rstn || flush_ex || stall || irq_trigger) begin

            id_ex_reg_we    <= 0;
            id_ex_mem_we    <= 0;
            id_ex_mem_re    <= 0;

            id_ex_is_branch <= 0;
            id_ex_is_jump   <= 0;
            id_ex_is_mret   <= 0;
            id_ex_is_wfi    <= 0;

            id_ex_rd        <= 0;

        end else if (!cpu_halt) begin

            id_ex_pc        <= if_id_pc;

            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_rd        <= id_rd;

            id_ex_rdata1    <= rf_read1;
            id_ex_rdata2    <= rf_read2;

            id_ex_alu_op2   <= id_alu_op2;

            id_ex_imm_b     <= id_imm_b;
            id_ex_imm_j     <= id_imm_j;
            id_ex_imm_u     <= id_imm_u;

            id_ex_opcode    <= id_opcode;
            id_ex_alu_ctrl  <= id_alu_ctrl;
            id_ex_funct3    <= id_funct3;

            id_ex_reg_we    <= id_reg_we;
            id_ex_mem_we    <= id_mem_we;
            id_ex_mem_re    <= id_mem_re;

            id_ex_is_branch <= id_is_branch;
            id_ex_is_jump   <= id_is_jump;
            id_ex_is_jalr   <= id_is_jalr;
            id_ex_is_auipc  <= id_is_auipc;
            id_ex_is_lui    <= id_is_lui;
            id_ex_is_mret   <= id_is_mret;
            id_ex_is_wfi    <= id_is_wfi;
        end
    end

    // -------------------------------------------------------------------------
    // Load-Use Hazard Detection
    // -------------------------------------------------------------------------
    // Stall the fetch/decode pipeline when the instruction currently in the
    // execute stage is a load whose destination register is required by the
    // instruction currently being decoded.
    assign stall =
        (id_ex_mem_re &&
        (id_ex_rd != 0) &&
        (id_ex_rd == id_rs1 || id_ex_rd == id_rs2));

    // =========================================================================
    // 3. EXECUTE (EX) AND DATA FORWARDING
    // =========================================================================

    // -------------------------------------------------------------------------
    // EX/MEM Pipeline State
    // -------------------------------------------------------------------------

    reg [31:0] ex_mem_alu_res;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_we;

    // -------------------------------------------------------------------------
    // MEM/WB Pipeline State
    // -------------------------------------------------------------------------

    reg [31:0] wb_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_we;

    // -------------------------------------------------------------------------
    // Forwarding Selection
    // -------------------------------------------------------------------------
    // Forward data from:
    // - EX/MEM stage when the most recent result is available
    // - MEM/WB stage when the result is available from writeback
    // - ID/EX register contents otherwise
    wire [1:0] forward_a =
        (ex_mem_reg_we &&
         ex_mem_rd != 0 &&
         ex_mem_rd == id_ex_rs1) ? 2'b10 :

        (mem_wb_reg_we &&
         mem_wb_rd != 0 &&
         mem_wb_rd == id_ex_rs1) ? 2'b01 :
        2'b00;

    wire [1:0] forward_b =
        (ex_mem_reg_we &&
         ex_mem_rd != 0 &&
         ex_mem_rd == id_ex_rs2) ? 2'b10 :

        (mem_wb_reg_we &&
         mem_wb_rd != 0 &&
         mem_wb_rd == id_ex_rs2) ? 2'b01 :
        2'b00;

    // Select forwarded or registered source operands.
    wire [31:0] fwd_rs1_data =
        (forward_a == 2'b10) ? ex_mem_alu_res :
        (forward_a == 2'b01) ? wb_data :
        id_ex_rdata1;

    wire [31:0] fwd_rs2_data =
        (forward_b == 2'b10) ? ex_mem_alu_res :
        (forward_b == 2'b01) ? wb_data :
        id_ex_rdata2;

    // -------------------------------------------------------------------------
    // ALU Operand Selection
    // -------------------------------------------------------------------------

    wire [31:0] alu_src_a =
        (id_ex_is_auipc || id_ex_is_jump) ? id_ex_pc :
        fwd_rs1_data;

    wire [31:0] alu_src_b;

    assign alu_src_b =
        (id_ex_is_auipc) ? id_ex_imm_u :
        (id_ex_is_jump)  ? 32'd4 :
        (id_ex_opcode == 7'h33) ? fwd_rs2_data :
        id_ex_alu_op2;

    // -------------------------------------------------------------------------
    // ALU Instance
    // -------------------------------------------------------------------------

    wire [31:0] alu_result;
    wire        alu_zero;

    vrm_alu alu_inst (
        .src_a  (alu_src_a),
        .src_b  (alu_src_b),
        .ctrl   (id_ex_alu_ctrl),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // -------------------------------------------------------------------------
    // Branch Comparison
    // -------------------------------------------------------------------------

    // Equality comparison.
    wire is_eq = (fwd_rs1_data == fwd_rs2_data);

    // Signed less-than comparison.
    wire is_lt =
        ($signed(fwd_rs1_data) < $signed(fwd_rs2_data));

    // Unsigned less-than comparison.
    wire is_ltu =
        (fwd_rs1_data < fwd_rs2_data);

    reg branch_cond;

    // Decode branch condition based on funct3.
    always @(*) begin
        case (id_ex_funct3)

            3'b000: branch_cond = is_eq;   // BEQ
            3'b001: branch_cond = !is_eq;  // BNE
            3'b100: branch_cond = is_lt;   // BLT
            3'b101: branch_cond = !is_lt;  // BGE
            3'b110: branch_cond = is_ltu;  // BLTU
            3'b111: branch_cond = !is_ltu; // BGEU

            default: branch_cond = 0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Branch and Jump Control
    // -------------------------------------------------------------------------

    // A branch is taken when its condition is true.
    // JAL and JALR are represented as jump operations.
    assign branch_taken_ex =
        (id_ex_is_branch && branch_cond) ||
        id_ex_is_jump;

    // Generate target PC:
    // - JALR uses rs1 + immediate with bit 0 cleared.
    // - JAL uses PC + J-type immediate.
    // - Conditional branches use PC + B-type immediate.
    assign target_pc_ex =
        id_ex_is_jalr ? (fwd_rs1_data + id_ex_alu_op2) & 32'hFFFFFFFE :
        id_ex_is_jump ? (id_ex_pc + id_ex_imm_j) :
        (id_ex_pc + id_ex_imm_b);

    assign is_mret_ex = id_ex_is_mret;

    // Flush younger pipeline stages after a taken control-flow instruction
    // or MRET operation.
    assign flush_ex =
        branch_taken_ex || is_mret_ex;

    // =========================================================================
    // EX/MEM PIPELINE REGISTER
    // =========================================================================

    reg [31:0] ex_mem_wdata;
    reg        ex_mem_mem_we;
    reg        ex_mem_mem_re;
    reg        ex_mem_is_wfi;

    // -------------------------------------------------------------------------
    // EX/MEM Pipeline Update
    // -------------------------------------------------------------------------
    always @(posedge clk) begin

        if (!rstn || irq_trigger) begin

            ex_mem_reg_we <= 0;
            ex_mem_mem_we <= 0;
            ex_mem_mem_re <= 0;
            ex_mem_rd     <= 0;
            ex_mem_is_wfi <= 0;

        end else if (!cpu_halt) begin

            // LUI uses its immediate directly as the final ALU result.
            ex_mem_alu_res <=
                id_ex_is_lui ? id_ex_imm_u : alu_result;

            ex_mem_wdata  <= fwd_rs2_data;
            ex_mem_rd     <= id_ex_rd;

            ex_mem_reg_we <= id_ex_reg_we;
            ex_mem_mem_we <= id_ex_mem_we;
            ex_mem_mem_re <= id_ex_mem_re;

            ex_mem_is_wfi <= id_ex_is_wfi;
        end
    end

    // =========================================================================
    // 4. MEMORY ACCESS (MEM)
    // =========================================================================

    // -------------------------------------------------------------------------
    // Data Memory Interface
    // -------------------------------------------------------------------------

    assign mem_addr  = ex_mem_alu_res;
    assign mem_wdata = ex_mem_wdata;
    assign mem_we    = ex_mem_mem_we;

    // -------------------------------------------------------------------------
    // MEM/WB Pipeline Register
    // -------------------------------------------------------------------------

    reg [31:0] mem_wb_alu_res;
    reg [31:0] mem_wb_mem_data;

    reg mem_wb_mem_re;
    reg mem_wb_is_wfi;

    // -------------------------------------------------------------------------
    // MEM/WB Pipeline Update
    // -------------------------------------------------------------------------
    always @(posedge clk) begin

        if (!rstn || irq_trigger) begin

            mem_wb_reg_we <= 0;
            mem_wb_rd     <= 0;
            mem_wb_is_wfi <= 0;

        end else if (!cpu_halt) begin

            mem_wb_alu_res  <= ex_mem_alu_res;
            mem_wb_mem_data <= mem_rdata;

            mem_wb_rd       <= ex_mem_rd;

            mem_wb_reg_we   <= ex_mem_reg_we;
            mem_wb_mem_re   <= ex_mem_mem_re;

            mem_wb_is_wfi   <= ex_mem_is_wfi;
        end
    end

    // =========================================================================
    // 5. WRITEBACK (WB)
    // =========================================================================

    // Select either memory data or ALU result as the value written to the
    // register file.
    always @(*) begin
        wb_data =
            mem_wb_mem_re ? mem_wb_mem_data :
            mem_wb_alu_res;
    end

    // -------------------------------------------------------------------------
    // Register File Writeback
    // -------------------------------------------------------------------------
    // Register x0 is protected from writes by excluding register index zero.
    always @(posedge clk) begin
        if (mem_wb_reg_we && mem_wb_rd != 0) begin
            reg_file[mem_wb_rd] <= wb_data;
        end
    end

    // =========================================================================
    // DEBUG OUTPUT
    // =========================================================================

    assign debug_reg_x1 = reg_file[1];

    // =========================================================================
    // CPU HALT CONTROL
    // =========================================================================
    // The processor remains halted while a WFI instruction is active.
    // An accepted interrupt clears the halt condition and allows execution
    // to resume.
    assign cpu_halt =
        mem_wb_is_wfi && !irq_trigger;

endmodule
