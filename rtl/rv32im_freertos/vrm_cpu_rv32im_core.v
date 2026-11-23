`timescale 1ns / 1ps

// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_cpu_rv32im_core
// DESCRIPTION : RV32IM processor core with a five-stage in-order pipeline
//               (IF, ID, EX, MEM, WB) and machine-mode traps.
//
// Features:
//   - RV32I base integer ISA plus the M extension (vrm_mdu). MUL* finish one
//     cycle after start; DIV*/REM* iterate 32 times while the pipeline holds.
//   - Full forwarding from EX/MEM and MEM/WB, register-file write-through,
//     and a one-bubble stall for load-use and dependent CSR hazards.
//   - Branches and jumps resolve in EX; the IF/ID and ID/EX stages are
//     flushed on a taken branch, jump, or MRET.
//   - Byte enables for SB/SH/SW; LB/LBU/LH/LHU are aligned in WB.
//   - Illegal-instruction detection in decode (mcause 2, mtval = encoding),
//     illegal CSR address (mcause 2), EBREAK (3), ECALL (11).
//   - Interrupts MEIP (11), MTIP (7), MSIP (3) through vrm_csr.
//   - WFI: no younger instruction is issued while WFI is in flight; the core
//     halts after WFI retires and wakes when (mip & mie) != 0, with or
//     without the global MIE bit.
//
// Interrupt Behavior:
//   - An interrupt is taken only while no M-extension instruction is in
//     EX, MEM, or WB and no MRET is in EX. The measured worst case from MTIP
//     to trap commit in the FreeRTOS testbench is 59 cycles during DIV.
//   - mepc receives the oldest instruction flushed by the interrupt
//     (ID/EX, else IF/ID, else the fetch PC).
//
// Memory Interface:
//   - Instruction fetch is combinational on pc_out / instr_in.
//   - Data access is issued from EX/MEM: mem_addr, mem_wdata, mem_be, mem_we;
//     mem_rdata is sampled into MEM/WB in the same cycle.
//
// Notes:
//   - Reduced scope: machine mode only; FENCE is decoded as a no-op;
//     misaligned loads and stores do not trap; there is no instruction or
//     data cache.
//   - WARNING: the trap target is csr_mtvec including its two mode bits.
//     Only direct mode (mtvec[1:0] = 00) is supported by the fetch logic;
//     vectored mode would produce a misaligned PC.
// ============================================================================

module vrm_cpu_rv32im_core (
    input  wire        clk,
    input  wire        rstn,

    // Interrupt lines
    input  wire        irq_ext,
    input  wire        irq_timer,
    input  wire        irq_sw,

    // Instruction memory
    output wire [31:0] pc_out,
    input  wire [31:0] instr_in,

    // Data memory
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_be,
    output wire        mem_we,
    input  wire [31:0] mem_rdata,

    // Debug
    output wire [31:0] debug_reg_x1,
    output wire        cpu_halt
);

    // =========================================================================
    // 0. GLOBAL SIGNALS AND PC
    // =========================================================================
    reg [31:0] pc;
    assign pc_out = pc;

    wire stall;
    wire mdu_hold;
    wire flush_ex;

    wire        core_ex_csr_en, core_ex_csr_illegal;
    wire [11:0] core_ex_csr_addr;
    wire [1:0]  core_ex_csr_op;
    wire [31:0] core_ex_csr_src, core_ex_csr_rdata;

    wire        core_trap_commit, core_trap_is_int, core_mret_commit;
    wire [31:0] core_trap_pc, core_trap_tval;
    wire [3:0]  core_trap_cause;

    wire [31:0] csr_mtvec, csr_mepc, csr_mie, csr_mip;
    wire        csr_int_pending, csr_mie_global;
    wire [3:0]  csr_int_cause;

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF)
    // =========================================================================
    reg [31:0] if_id_pc, if_id_instr;
    reg        if_id_valid;

    wire        branch_taken_ex;
    wire [31:0] target_pc_ex;
    wire        is_mret_ex;

    // PC priority: trap > MRET > taken branch/jump > sequential.
    always @(posedge clk) begin
        if (!rstn) begin
            pc <= 32'h0;
        end else if (!cpu_halt || core_trap_commit || core_mret_commit) begin
            if (core_trap_commit)      pc <= csr_mtvec;
            else if (core_mret_commit) pc <= csr_mepc;
            else if (branch_taken_ex)  pc <= target_pc_ex;
            else if (!stall && !mdu_hold) pc <= pc + 4;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            if_id_instr <= 32'h00000013;   // NOP
            if_id_pc    <= 32'h0;
            if_id_valid <= 1'b0;
        end else if (flush_ex || core_trap_commit) begin
            if_id_instr <= 32'h00000013;
            if_id_valid <= 1'b0;
        end else if (!stall && !mdu_hold && !cpu_halt) begin
            if_id_instr <= instr_in;
            if_id_pc    <= pc;
            if_id_valid <= 1'b1;
        end
    end

    // =========================================================================
    // 2. INSTRUCTION DECODE (ID)
    // =========================================================================
    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1    = if_id_instr[19:15];
    wire [4:0] id_rs2    = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    wire [31:0] id_imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
    wire [31:0] id_imm_s = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    wire [31:0] id_imm_b = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    wire [31:0] id_imm_u = {if_id_instr[31:12], 12'h0};
    wire [31:0] id_imm_j = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};

    reg [31:0] reg_file [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) reg_file[i] = 0;

    wire [31:0] wb_data;
    reg [4:0] mem_wb_rd;
    reg       mem_wb_reg_we;

    // Register read with write-through of the value being written back.
    wire [31:0] rf_read1 = (id_rs1 == 0) ? 32'b0 : (mem_wb_reg_we && mem_wb_rd == id_rs1) ? wb_data : reg_file[id_rs1];
    wire [31:0] rf_read2 = (id_rs2 == 0) ? 32'b0 : (mem_wb_reg_we && mem_wb_rd == id_rs2) ? wb_data : reg_file[id_rs2];

    reg [3:0] id_alu_ctrl;
    reg id_reg_we, id_mem_we, id_mem_re;
    reg id_is_branch, id_is_jump, id_is_jalr, id_is_auipc, id_is_lui;
    reg uses_rs1, uses_rs2;

    wire id_is_mret = (id_opcode == 7'h73) && (if_id_instr == 32'h30200073);
    wire id_is_wfi  = (id_opcode == 7'h73) && (if_id_instr == 32'h10500073);
    wire id_is_csr  = (id_opcode == 7'h73) && (id_funct3 != 3'b000);

    wire [1:0] id_csr_op   = id_funct3[1:0] - 2'b01;
    wire       id_csr_imm  = id_funct3[2];
    wire [4:0] id_csr_uimm = id_rs1;
    wire id_is_m_ext       = (id_opcode == 7'h33) && (id_funct7 == 7'b0000001);

    // Combinational illegal-instruction detection: every encoding is illegal
    // unless a supported opcode below clears the flag.
    reg id_is_illegal_dec;

    always @(*) begin
        id_reg_we = 1'b0; id_mem_we = 1'b0; id_mem_re = 1'b0;
        id_is_branch = 1'b0; id_is_jump = 1'b0; id_is_jalr = 1'b0;
        id_is_auipc = 1'b0; id_is_lui = 1'b0;
        id_alu_ctrl = 4'b0000; uses_rs1 = 1'b0; uses_rs2 = 1'b0;

        id_is_illegal_dec = 1'b1;

        case (id_opcode)
            7'h37: begin id_is_lui = 1'b1; id_reg_we = 1'b1; id_is_illegal_dec = 1'b0; end
            7'h17: begin id_is_auipc = 1'b1; id_reg_we = 1'b1; id_is_illegal_dec = 1'b0; end
            7'h6F: begin id_is_jump = 1'b1; id_reg_we = 1'b1; id_is_illegal_dec = 1'b0; end
            7'h67: begin id_is_jump = 1'b1; id_is_jalr = 1'b1; id_reg_we = 1'b1; uses_rs1 = 1'b1; id_is_illegal_dec = 1'b0; end
            7'h63: begin id_is_branch = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; id_is_illegal_dec = 1'b0; end
            7'h03: begin id_mem_re = 1'b1; id_reg_we = 1'b1; uses_rs1 = 1'b1; id_alu_ctrl = 4'b0000; id_is_illegal_dec = 1'b0; end
            7'h23: begin id_mem_we = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; id_alu_ctrl = 4'b0000; id_is_illegal_dec = 1'b0; end
            7'h0F: begin id_is_illegal_dec = 1'b0; end
            7'h13: begin
                id_reg_we = 1'b1; uses_rs1 = 1'b1; id_is_illegal_dec = 1'b0;

                // Shift-immediate encodings: SLLI needs funct7 0x00,
                // SRLI/SRAI need 0x00 or 0x20.
                if (id_funct3 == 3'b001 && id_funct7 != 7'h00) id_is_illegal_dec = 1'b1;
                if (id_funct3 == 3'b101 && id_funct7 != 7'h00 && id_funct7 != 7'h20) id_is_illegal_dec = 1'b1;

                case (id_funct3)
                    3'b000: id_alu_ctrl = 4'b0000;
                    3'b010: id_alu_ctrl = 4'b0011;
                    3'b011: id_alu_ctrl = 4'b1010;
                    3'b100: id_alu_ctrl = 4'b0100;
                    3'b110: id_alu_ctrl = 4'b0110;
                    3'b111: id_alu_ctrl = 4'b0111;
                    3'b001: id_alu_ctrl = 4'b0010;
                    3'b101: id_alu_ctrl = (id_funct7[5]) ? 4'b1000 : 4'b0101;
                    default: id_alu_ctrl = 4'b0000;
                endcase
            end
            7'h33: begin
                id_reg_we = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; id_is_illegal_dec = 1'b0;
                if (id_is_m_ext) begin
                    id_alu_ctrl = 4'b0000;
                end else begin
                    // Base OP: funct7 must be 0x00 or 0x20, and 0x20 is only
                    // valid for SUB (funct3 000) and SRA (funct3 101).
                    if (id_funct7 != 7'h00 && id_funct7 != 7'h20) id_is_illegal_dec = 1'b1;
                    if (id_funct7 == 7'h20 && id_funct3 != 3'b000 && id_funct3 != 3'b101) id_is_illegal_dec = 1'b1;

                    case (id_funct3)
                        3'b000: id_alu_ctrl = (id_funct7[5]) ? 4'b0001 : 4'b0000;
                        3'b001: id_alu_ctrl = 4'b0010;
                        3'b010: id_alu_ctrl = 4'b0011;
                        3'b011: id_alu_ctrl = 4'b1010;
                        3'b100: id_alu_ctrl = 4'b0100;
                        3'b101: id_alu_ctrl = (id_funct7[5]) ? 4'b1000 : 4'b0101;
                        3'b110: id_alu_ctrl = 4'b0110;
                        3'b111: id_alu_ctrl = 4'b0111;
                        default: id_alu_ctrl = 4'b0000;
                    endcase
                end
            end
            7'h73: begin
                // SYSTEM: funct3 100 is unallocated and stays illegal.
                if (id_is_csr && id_funct3 != 3'b100) begin
                    id_reg_we = 1'b1; uses_rs1 = !id_csr_imm;
                    id_is_illegal_dec = 1'b0;
                end else if (id_funct3 == 3'b000) begin
                    if (if_id_instr == 32'h00000073 || // ECALL
                        if_id_instr == 32'h00100073 || // EBREAK
                        if_id_instr == 32'h30200073 || // MRET
                        if_id_instr == 32'h10500073)   // WFI
                    begin
                        id_is_illegal_dec = 1'b0;
                    end
                end
            end
        endcase
    end

    wire [31:0] id_alu_op2 = (id_opcode == 7'h33 || id_is_branch) ? rf_read2 : (id_opcode == 7'h23) ? id_imm_s : id_imm_i;

    // ID/EX pipeline register
    reg [31:0] id_ex_pc, id_ex_rdata1, id_ex_rdata2, id_ex_imm_b, id_ex_imm_j, id_ex_imm_u, id_ex_alu_op2;
    reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg [3:0]  id_ex_alu_ctrl;
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_opcode, id_ex_funct7;
    reg        id_ex_reg_we, id_ex_mem_we, id_ex_mem_re;
    reg        id_ex_is_wfi, id_ex_is_branch, id_ex_is_jump, id_ex_is_jalr, id_ex_is_auipc, id_ex_is_lui, id_ex_is_mret;
    reg        id_ex_is_csr;
    reg [11:0] id_ex_csr_addr;
    reg [1:0]  id_ex_csr_op;
    reg        id_ex_csr_imm;
    reg [4:0]  id_ex_csr_uimm;
    reg        id_ex_valid;

    // Illegal flag and encoding travel to EX for the trap and mtval.
    reg        id_ex_is_illegal;
    reg [31:0] id_ex_instr;

    // Hazard detection
    wire load_use_hazard = (id_ex_mem_re && (id_ex_rd != 0) && ((uses_rs1 && (id_ex_rd == id_rs1)) || (uses_rs2 && (id_ex_rd == id_rs2))));
    wire csr_hazard = id_is_csr && id_ex_is_csr && (id_csr_op != 2'b00 || id_ex_csr_op != 2'b00) && (if_id_instr[31:20] == id_ex_csr_addr);
    // Drain WFI to retirement without issuing an instruction behind it.
    // IF/ID retains the resume PC for both wake without a trap and IRQ entry.
    reg ex_mem_is_wfi, ex_mem_valid, mem_wb_is_wfi, mem_wb_valid;
    wire wfi_in_flight = (id_ex_valid && id_ex_is_wfi) ||
                         (ex_mem_valid && ex_mem_is_wfi) ||
                         (mem_wb_valid && mem_wb_is_wfi);
    assign stall = load_use_hazard || csr_hazard || wfi_in_flight;

    always @(posedge clk) begin
        if (!rstn || flush_ex || core_trap_commit) begin
            id_ex_reg_we <= 1'b0; id_ex_mem_we <= 1'b0; id_ex_mem_re <= 1'b0;
            id_ex_is_branch <= 1'b0; id_ex_is_jump <= 1'b0; id_ex_is_mret <= 1'b0; id_ex_is_wfi <= 1'b0; id_ex_is_csr <= 1'b0;
            id_ex_rd <= 5'b0; id_ex_opcode <= 7'b0; id_ex_funct7 <= 7'b0; id_ex_valid <= 1'b0;
            id_ex_is_illegal <= 1'b0;
            id_ex_instr      <= 32'h0;
        end else if (mdu_hold) begin
            // Hold: ID/EX keeps its contents while the MDU works.
        end else if (stall) begin
            id_ex_reg_we <= 1'b0; id_ex_mem_we <= 1'b0; id_ex_mem_re <= 1'b0;
            id_ex_is_branch <= 1'b0; id_ex_is_jump <= 1'b0; id_ex_is_mret <= 1'b0; id_ex_is_wfi <= 1'b0; id_ex_is_csr <= 1'b0;
            id_ex_rd <= 5'b0; id_ex_opcode <= 7'b0; id_ex_funct7 <= 7'b0; id_ex_valid <= 1'b0;
            id_ex_is_illegal <= 1'b0;
            id_ex_instr      <= 32'h0;
        end else if (!cpu_halt) begin
            id_ex_pc <= if_id_pc; id_ex_rs1 <= id_rs1; id_ex_rs2 <= id_rs2; id_ex_rd <= id_rd;
            id_ex_rdata1 <= rf_read1; id_ex_rdata2 <= rf_read2; id_ex_alu_op2 <= id_alu_op2;
            id_ex_imm_b <= id_imm_b; id_ex_imm_j <= id_imm_j; id_ex_imm_u <= id_imm_u;
            id_ex_opcode <= id_opcode; id_ex_alu_ctrl <= id_alu_ctrl; id_ex_funct3 <= id_funct3; id_ex_funct7 <= id_funct7;
            id_ex_reg_we <= id_reg_we; id_ex_mem_we <= id_mem_we; id_ex_mem_re <= id_mem_re;
            id_ex_is_branch <= id_is_branch; id_ex_is_jump <= id_is_jump; id_ex_is_jalr <= id_is_jalr;
            id_ex_is_auipc <= id_is_auipc; id_ex_is_lui <= id_is_lui; id_ex_is_mret <= id_is_mret; id_ex_is_wfi <= id_is_wfi;
            id_ex_is_csr <= id_is_csr; id_ex_csr_addr <= if_id_instr[31:20]; id_ex_csr_op <= id_csr_op;
            id_ex_csr_imm <= id_csr_imm; id_ex_csr_uimm <= id_csr_uimm; id_ex_valid <= if_id_valid;

            // Only a valid instruction can be flagged illegal.
            id_ex_is_illegal <= id_is_illegal_dec && if_id_valid;
            id_ex_instr      <= if_id_instr;
        end
    end

    // =========================================================================
    // 3. EXECUTE (EX) AND MDU
    // =========================================================================
    reg [31:0] ex_mem_alu_res;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_we;
    reg [31:0] ex_mem_csr_rdata;
    reg        ex_mem_is_csr;

    wire id_ex_is_m_ext = (id_ex_opcode == 7'h33) && (id_ex_funct7 == 7'b0000001);
    reg [2:0] mdu_op;
    always @(*) begin
        case (id_ex_funct3)
            3'b000: mdu_op = 3'b000; 3'b001: mdu_op = 3'b001; 3'b010: mdu_op = 3'b010; 3'b011: mdu_op = 3'b011;
            3'b100: mdu_op = 3'b100; 3'b101: mdu_op = 3'b101; 3'b110: mdu_op = 3'b110; 3'b111: mdu_op = 3'b111;
            default: mdu_op = 3'b000;
        endcase
    end

    wire [31:0] mdu_result;
    wire        mdu_done, mdu_busy;
    reg         mdu_active_r;
    wire        mdu_start = id_ex_is_m_ext && !mdu_active_r;
    assign      mdu_hold = id_ex_is_m_ext && !mdu_done;
    wire        mdu_rstn = rstn && !core_trap_commit;

    always @(posedge clk) begin
        if (!rstn || core_trap_commit || flush_ex) mdu_active_r <= 1'b0;
        else if (mdu_start) mdu_active_r <= 1'b1;
        else if (mdu_done)  mdu_active_r <= 1'b0;
    end

    // -------------------------------------------------------------------------
    // EX-stage forwarding
    // -------------------------------------------------------------------------
    wire [1:0] forward_a = (ex_mem_reg_we && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1)) ? 2'b10 :
                           (mem_wb_reg_we && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1)) ? 2'b01 : 2'b00;

    wire [1:0] forward_b = (ex_mem_reg_we && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2)) ? 2'b10 :
                           (mem_wb_reg_we && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs2)) ? 2'b01 : 2'b00;

    // A CSR instruction in MEM forwards the old CSR value, not the ALU result.
    wire [31:0] ex_mem_fwd_data = ex_mem_is_csr ? ex_mem_csr_rdata : ex_mem_alu_res;

    wire [31:0] fwd_rs1_data = (forward_a == 2'b10) ? ex_mem_fwd_data :
                               (forward_a == 2'b01) ? wb_data : id_ex_rdata1;

    wire [31:0] fwd_rs2_data = (forward_b == 2'b10) ? ex_mem_fwd_data :
                               (forward_b == 2'b01) ? wb_data : id_ex_rdata2;

    vrm_mdu mdu_inst (
        .clk(clk), .rstn(mdu_rstn), .start(mdu_start), .op(mdu_op),
        .src_a(fwd_rs1_data), .src_b(fwd_rs2_data), .result(mdu_result), .done(mdu_done), .busy(mdu_busy)
    );

    wire [31:0] alu_src_a = (id_ex_is_auipc || id_ex_is_jump) ? id_ex_pc : fwd_rs1_data;
    wire [31:0] alu_src_b = (id_ex_is_auipc) ? id_ex_imm_u : (id_ex_is_jump) ? 32'd4 : (id_ex_opcode == 7'h33) ? fwd_rs2_data : id_ex_alu_op2;
    wire [31:0] alu_result;
    wire        alu_zero;

    vrm_alu alu_inst (
        .src_a(alu_src_a), .src_b(alu_src_b), .ctrl(id_ex_alu_ctrl), .result(alu_result), .zero(alu_zero)
    );

    wire [31:0] ex_result = id_ex_is_lui ? id_ex_imm_u : id_ex_is_m_ext ? mdu_result : alu_result;

    wire is_eq  = (fwd_rs1_data == fwd_rs2_data);
    wire is_lt  = ($signed(fwd_rs1_data) < $signed(fwd_rs2_data));
    wire is_ltu = (fwd_rs1_data < fwd_rs2_data);
    reg branch_cond;
    always @(*) begin
        case (id_ex_funct3)
            3'b000: branch_cond = is_eq; 3'b001: branch_cond = !is_eq; 3'b100: branch_cond = is_lt;
            3'b101: branch_cond = !is_lt; 3'b110: branch_cond = is_ltu; 3'b111: branch_cond = !is_ltu;
            default: branch_cond = 1'b0;
        endcase
    end

    assign branch_taken_ex = (id_ex_is_branch && branch_cond) || id_ex_is_jump;
    assign target_pc_ex = id_ex_is_jalr ? ((fwd_rs1_data + id_ex_alu_op2) & 32'hFFFFFFFE) :
                          id_ex_is_jump ? (id_ex_pc + id_ex_imm_j) : (id_ex_pc + id_ex_imm_b);
    assign is_mret_ex = id_ex_is_mret;
    assign flush_ex = branch_taken_ex || is_mret_ex;

    wire [31:0] csr_src_val = id_ex_csr_imm ? {27'b0, id_ex_csr_uimm} : fwd_rs1_data;

    // An illegal instruction never enables a CSR write.
    assign core_ex_csr_en   = id_ex_is_csr && !id_ex_is_illegal;

    assign core_ex_csr_addr = id_ex_csr_addr;
    assign core_ex_csr_op   = id_ex_csr_op;
    assign core_ex_csr_src  = csr_src_val;

    // =========================================================================
    // 4. TRAP DETECTION AND COMMIT
    // =========================================================================
    reg ex_mem_is_m_ext, mem_wb_is_m_ext;
    wire mdu_in_flight = id_ex_is_m_ext || ex_mem_is_m_ext || mem_wb_is_m_ext;

    wire ex_illegal_csr = id_ex_is_csr && core_ex_csr_illegal;
    wire ex_is_ecall  = (id_ex_opcode == 7'h73) && (id_ex_funct3 == 3'b000) && (id_ex_csr_addr == 12'h000);
    wire ex_is_ebreak = (id_ex_opcode == 7'h73) && (id_ex_funct3 == 3'b000) && (id_ex_csr_addr == 12'h001);

    // Illegal instructions trap with mcause 2 and mtval = encoding.
    wire        ex_trap_req   = id_ex_is_illegal || ex_illegal_csr || ex_is_ecall || ex_is_ebreak;

    // Priority: illegal instruction (2) > illegal CSR (2) > breakpoint (3) > ECALL (11)
    wire [3:0]  ex_trap_cause = id_ex_is_illegal ? 4'd2 :
                                ex_illegal_csr   ? 4'd2 :
                                ex_is_ebreak     ? 4'd3 : 4'd11;

    wire [31:0] ex_trap_tval  = id_ex_is_illegal ? id_ex_instr :
                                ex_illegal_csr   ? {20'b0, id_ex_csr_addr} : 32'h0;

    wire int_trap_taken = csr_int_pending && !mdu_in_flight && !id_ex_is_mret;
    wire ex_trap_taken = ex_trap_req && !int_trap_taken;

    assign core_trap_commit = int_trap_taken || ex_trap_taken;

    // An interrupt resumes at the oldest instruction flushed by the trap.
    assign core_trap_pc = !int_trap_taken   ? id_ex_pc :
                          id_ex_valid       ? id_ex_pc :
                          if_id_valid       ? if_id_pc : pc;

    assign core_trap_cause  = int_trap_taken ? csr_int_cause : ex_trap_cause;
    assign core_trap_is_int = int_trap_taken;
    assign core_trap_tval   = int_trap_taken ? 32'h0 : ex_trap_tval;
    assign core_mret_commit = id_ex_is_mret;

    // Store data replication and byte enables for SB/SH/SW
    reg [31:0] store_data;
    reg [3:0]  store_be;
    always @(*) begin
        store_data = fwd_rs2_data; store_be = 4'b1111;
        if (id_ex_mem_we) begin
            case (id_ex_funct3[1:0])
                2'b00: begin store_be = 4'b0001 << alu_result[1:0]; store_data = {4{fwd_rs2_data[7:0]}}; end
                2'b01: begin store_be = 4'b0011 << {alu_result[1], 1'b0}; store_data = {2{fwd_rs2_data[15:0]}}; end
                default: begin store_be = 4'b1111; store_data = fwd_rs2_data; end
            endcase
        end
    end

    // EX/MEM register
    reg [31:0] ex_mem_wdata;
    reg [3:0]  ex_mem_be;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_mem_we, ex_mem_mem_re;

    always @(posedge clk) begin
        if (!rstn || core_trap_commit) begin
            ex_mem_reg_we <= 1'b0; ex_mem_mem_we <= 1'b0; ex_mem_mem_re <= 1'b0;
            ex_mem_rd <= 5'b0; ex_mem_is_wfi <= 1'b0; ex_mem_be <= 4'b0000;
            ex_mem_is_csr <= 1'b0; ex_mem_is_m_ext <= 1'b0; ex_mem_valid <= 1'b0;
        end else if (mdu_hold) begin
            ex_mem_reg_we <= 1'b0; ex_mem_mem_we <= 1'b0; ex_mem_mem_re <= 1'b0;
            ex_mem_rd <= 5'b0; ex_mem_is_wfi <= 1'b0; ex_mem_be <= 4'b0000;
            ex_mem_is_csr <= 1'b0; ex_mem_is_m_ext <= 1'b0; ex_mem_valid <= 1'b0;
        end else if (!cpu_halt) begin
            ex_mem_alu_res <= ex_result; ex_mem_wdata <= store_data; ex_mem_be <= store_be;
            ex_mem_funct3 <= id_ex_funct3; ex_mem_rd <= id_ex_rd;
            ex_mem_reg_we <= id_ex_reg_we; ex_mem_mem_we <= id_ex_mem_we; ex_mem_mem_re <= id_ex_mem_re;
            ex_mem_is_wfi <= id_ex_is_wfi; ex_mem_csr_rdata <= core_ex_csr_rdata;
            ex_mem_is_csr <= id_ex_is_csr; ex_mem_is_m_ext <= id_ex_is_m_ext; ex_mem_valid <= id_ex_valid;
        end
    end

    // =========================================================================
    // 5. MEMORY ACCESS (MEM)
    // =========================================================================
    assign mem_addr = ex_mem_alu_res;
    assign mem_wdata = ex_mem_wdata;
    assign mem_we = ex_mem_mem_we;
    assign mem_be = ex_mem_be;

    reg [31:0] mem_wb_alu_res, mem_wb_mem_data, mem_wb_csr_rdata;
    reg [2:0]  mem_wb_funct3;
    reg        mem_wb_mem_re, mem_wb_is_csr;

    always @(posedge clk) begin
        if (!rstn) begin
            mem_wb_reg_we <= 1'b0; mem_wb_rd <= 5'b0; mem_wb_is_wfi <= 1'b0;
            mem_wb_is_csr <= 1'b0; mem_wb_is_m_ext <= 1'b0; mem_wb_valid <= 1'b0;
        end else if (!cpu_halt) begin
            mem_wb_alu_res <= ex_mem_alu_res; mem_wb_mem_data <= mem_rdata; mem_wb_funct3 <= ex_mem_funct3;
            mem_wb_rd <= ex_mem_rd; mem_wb_reg_we <= ex_mem_reg_we; mem_wb_mem_re <= ex_mem_mem_re;
            mem_wb_is_wfi <= ex_mem_is_wfi; mem_wb_csr_rdata <= ex_mem_csr_rdata;
            mem_wb_is_csr <= ex_mem_is_csr; mem_wb_is_m_ext <= ex_mem_is_m_ext; mem_wb_valid <= ex_mem_valid;
        end
    end

    // =========================================================================
    // 6. WRITEBACK (WB) AND RETIRE
    // =========================================================================
    reg [31:0] load_data_formatted;
    wire [1:0] load_byte_offset = mem_wb_alu_res[1:0];
    wire [31:0] mem_rdata_shifted = mem_wb_mem_data >> ({load_byte_offset, 3'b000});

    always @(*) begin
        if (mem_wb_mem_re) begin
            case (mem_wb_funct3)
                3'b000: load_data_formatted = {{24{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0]};
                3'b001: load_data_formatted = {{16{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0]};
                3'b010: load_data_formatted = mem_rdata_shifted;
                3'b100: load_data_formatted = {24'b0, mem_rdata_shifted[7:0]};
                3'b101: load_data_formatted = {16'b0, mem_rdata_shifted[15:0]};
                default: load_data_formatted = mem_rdata_shifted;
            endcase
        end else load_data_formatted = 32'b0;
    end

    assign wb_data = mem_wb_is_csr ? mem_wb_csr_rdata : mem_wb_mem_re ? load_data_formatted : mem_wb_alu_res;

    always @(posedge clk) begin
        if (mem_wb_reg_we && (mem_wb_rd != 5'd0)) reg_file[mem_wb_rd] <= wb_data;
    end

    // One retire pulse per instruction, also while the core is halted.
    reg mem_wb_retired;
    always @(posedge clk) begin
        if (!rstn || !cpu_halt) mem_wb_retired <= 1'b0;
        else if (mem_wb_valid)  mem_wb_retired <= 1'b1;
    end
    wire instr_retire = mem_wb_valid && !mem_wb_retired;

    // =========================================================================
    // 7. CSR BLOCK
    // =========================================================================
    vrm_csr csr_inst (
        .clk(clk), .rstn(rstn), .ex_csr_en(core_ex_csr_en), .ex_csr_addr(core_ex_csr_addr),
        .ex_csr_op(core_ex_csr_op), .ex_csr_src(core_ex_csr_src), .ex_csr_rdata(core_ex_csr_rdata),
        .ex_csr_illegal(core_ex_csr_illegal), .trap_commit(core_trap_commit), .trap_pc(core_trap_pc),
        .trap_cause(core_trap_cause), .trap_is_int(core_trap_is_int), .trap_tval(core_trap_tval),
        .mret_commit(core_mret_commit), .instr_retire(instr_retire), .irq_ext(irq_ext),
        .irq_timer(irq_timer), .irq_sw(irq_sw), .csr_mtvec(csr_mtvec), .csr_mepc(csr_mepc),
        .csr_mie_global(csr_mie_global), .csr_mie(csr_mie), .csr_mip(csr_mip),
        .csr_int_pending(csr_int_pending), .csr_int_cause(csr_int_cause), .csr_mcycle(), .csr_minstret()
    );

    assign debug_reg_x1 = reg_file[1];

    // =========================================================================
    // 8. WFI HALT STATE
    // =========================================================================
    // cpu_halt is a flip-flop: set when WFI retires without a wake request,
    // cleared by a trap commit or by a wake request ((mip & mie) != 0, or an
    // interrupt pending). It does not depend on WFI staying in MEM/WB.
    wire wfi_wake_req = |(csr_mip & csr_mie) || csr_int_pending;

    reg wfi_halt_state;
    always @(posedge clk) begin
        if (!rstn) begin
            wfi_halt_state <= 1'b0;
        end else if (core_trap_commit) begin
            wfi_halt_state <= 1'b0;   // a trap wakes the CPU
        end else if (wfi_wake_req) begin
            wfi_halt_state <= 1'b0;   // enabled interrupt: do not halt / release
        end else if (mem_wb_is_wfi && mem_wb_valid) begin
            wfi_halt_state <= 1'b1;   // WFI retired, no wake: halt
        end
    end

    assign cpu_halt = wfi_halt_state;

endmodule
