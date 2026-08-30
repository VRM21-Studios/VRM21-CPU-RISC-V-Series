`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_cpu_rv64_core
// Description : 64-bit RISC-V processor core implementing the RV64IMFD
//               architecture variant.
//
// Supported Architecture:
// - RV64I  : 64-bit base integer instruction set
// - M      : Integer multiplication and division
// - F      : Single-precision floating-point operations
// - D      : Double-precision floating-point operations
//
// Core Features:
// - Five-stage-style pipeline organization:
//     IF  - Instruction Fetch
//     ID  - Instruction Decode and Register Read
//     EX  - Execute
//     MEM - Memory Access
//     WB  - Writeback
// - Integer register file (GPR) with 32 x 64-bit registers.
// - Floating-point register file (FPR) with 32 x 64-bit registers.
// - RV64 integer ALU with 32-bit word-operation support.
// - Integer multiply/divide unit (MDU).
// - Floating-point execution unit interface.
// - Integer and floating-point data forwarding.
// - Load-use hazard handling.
// - MDU and FPU execution stall handling.
// - Branch and jump handling.
// - Machine interrupt and MRET support.
// - WFI support.
// - 64-bit load/store interface with byte write strobes.
// - Integer and floating-point load/store support.
// - Floating-point to integer and integer to floating-point register routing.
//
// Verification Status:
// - RV64IMFD FPGA verification: Not yet verified.
// - The integrated VRM21 FPU is maintained separately and has been
//   independently validated on FPGA.
//
// Notes:
// - This module is intended for synthesizable RTL implementation.
// - The FPU implementation is provided by the separate VRM21 FPU Series.
// ============================================================================

module vrm_cpu_rv64_core (
    input  wire        clk,
    input  wire        rstn,
    input  wire        irq,
    
    // Instruction Memory Interface (IF)
    output wire [63:0] pc_out,
    input  wire [31:0] instr_in,
    
    // Data Memory Interface (MEM)
    output wire [63:0] mem_addr,
    output wire [63:0] mem_wdata,
    output wire        mem_we, 
    input  wire [63:0] mem_rdata,
    input  wire        mem_busy,
    output wire [7:0]  mem_wstrb,
    
    output wire [63:0] debug_reg_x1,
    output wire        cpu_halt
);

    // =========================================================================
    // GLOBAL SIGNALS AND HAZARD CONTROL
    // =========================================================================

    reg [63:0] pc;
    assign pc_out = pc;

    wire flush_ex;      
    
    // Hazard control signals.
    wire stall_load_use;
    wire stall_mdu;
    wire stall_fpu; 
    
    // Pipeline stall conditions.
    // The IF/ID pipeline is held when a load-use hazard, MDU operation,
    // FPU operation, or busy memory transaction is active.
    wire stall_if_id = stall_load_use || stall_mdu || stall_fpu || mem_busy;
    
    // The EX stage is held while a multi-cycle operation or memory transaction
    // is active.
    wire stall_ex    = stall_mdu || stall_fpu || mem_busy;
    
    // The MEM stage is held while the external memory interface is busy.
    wire stall_mem   = mem_busy; 
    
    // Flush the ID/EX pipeline register on load-use hazards, control-flow
    // changes, or an interrupt request.
    wire flush_id_ex = stall_load_use || flush_ex || irq_trigger;

    reg in_isr;
    reg [63:0] mepc;
    
    // Interrupts are accepted only when the processor is not already inside
    // an interrupt service routine.
    wire irq_trigger = (irq === 1'b1) && !in_isr;

    // =========================================================================
    // INSTRUCTION FETCH (IF)
    // =========================================================================

    reg [63:0] if_id_pc;
    reg [31:0] if_id_instr;

    wire branch_taken_ex;  
    wire [63:0] target_pc_ex; 
    wire is_mret_ex;

    // Program counter and interrupt state update.
    always @(posedge clk) begin
        if (!rstn) begin
            pc <= 64'h0000000000004000;
            in_isr <= 0;
            mepc <= 0;
        end else begin
            if (irq_trigger) begin
                pc <= 64'h0000000000004004; 
                mepc <= (cpu_halt) ? pc : pc; 
                in_isr <= 1;
            end else if (is_mret_ex) begin
                pc <= mepc;
                in_isr <= 0;
            end else if (!cpu_halt) begin 
                if (branch_taken_ex) begin
                    pc <= target_pc_ex;
                end else if (!stall_if_id) begin
                    pc <= pc + 4;
                end
            end
        end
    end

    // IF/ID pipeline register.
    // A NOP is inserted whenever the instruction stream must be flushed.
    always @(posedge clk) begin
        if (!rstn || flush_ex || irq_trigger || is_mret_ex) begin
            if_id_instr <= 32'h00000013; // NOP
            if_id_pc    <= 64'h0;
        end else if (!stall_if_id && !cpu_halt) begin
            if_id_instr <= instr_in;
            if_id_pc    <= pc;
        end
    end

    // =========================================================================
    // INSTRUCTION DECODE (ID) AND REGISTER READ
    // =========================================================================

    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1    = if_id_instr[19:15];
    wire [4:0] id_rs2    = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    // Immediate value generation with sign extension.
    wire [63:0] id_imm_i = {{52{if_id_instr[31]}}, if_id_instr[31:20]};
    wire [63:0] id_imm_s = {{52{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    wire [63:0] id_imm_b = {{51{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    wire [63:0] id_imm_u = {{32{if_id_instr[31]}}, if_id_instr[31:12], 12'h0};
    wire [63:0] id_imm_j = {{43{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};

    // =========================================================================
    // REGISTER FILES
    // =========================================================================

    // General-purpose integer register file.
    // X0 is architecturally hard-wired to zero through the read logic.
    reg [63:0] reg_file [0:31];

    // Floating-point register file.
    reg [63:0] freg_file [0:31];
    
    integer i;

    // Simulation-time initialization of both register files.
    initial begin
        for (i=0; i<32; i=i+1) begin
            reg_file[i] = 0;
            freg_file[i] = 0;
        end
    end

    // =========================================================================
    // WRITEBACK BYPASS FOR REGISTER READ
    // =========================================================================

    // Writeback data used by the internal register-file bypass paths.
    reg [63:0] wb_data, wb_fdata; 
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_we, mem_wb_freg_we;

    // General-purpose register reads with writeback bypass.
    wire [63:0] rf_read1 = (id_rs1 == 0) ? 64'b0 : (mem_wb_reg_we && mem_wb_rd == id_rs1) ? wb_data : reg_file[id_rs1];
    wire [63:0] rf_read2 = (id_rs2 == 0) ? 64'b0 : (mem_wb_reg_we && mem_wb_rd == id_rs2) ? wb_data : reg_file[id_rs2];

    // Floating-point register reads with writeback bypass.
    wire [63:0] frf_read1 = (mem_wb_freg_we && mem_wb_rd == id_rs1) ? wb_fdata : freg_file[id_rs1];
    wire [63:0] frf_read2 = (mem_wb_freg_we && mem_wb_rd == id_rs2) ? wb_fdata : freg_file[id_rs2];

    // =========================================================================
    // CONTROL DECODER
    // =========================================================================

    reg [4:0] id_alu_ctrl;
    reg id_reg_we, id_freg_we, id_mem_we, id_mem_re;
    reg id_is_branch, id_is_jump, id_is_jalr, id_is_auipc, id_is_lui;
    
    // -------------------------------------------------------------------------
    // MDU DECODER
    // -------------------------------------------------------------------------

    // Detect RV64M integer multiply/divide instructions.
    wire id_is_mdu = ((id_opcode == 7'h33) || (id_opcode == 7'h3B)) && (id_funct7 == 7'b0000001);
    wire [3:0] id_mdu_op = {(id_opcode == 7'h3B), id_funct3};
    
    // -------------------------------------------------------------------------
    // FPU DECODER
    // -------------------------------------------------------------------------

    // Floating-point computational instructions use opcode 0x53.
    wire id_is_fpu = (id_opcode == 7'h53); 
    reg [3:0] id_fpu_op;
    
    // -------------------------------------------------------------------------
    // CROSS-REGISTER GPR/FPR ROUTING
    // -------------------------------------------------------------------------

    // Floating-point result written to the integer register file:
    // FCMP, FCVT.int.fmt, FMV.X.fmt, and FCLASS.
    wire fpu_to_gpr = id_is_fpu && (id_funct7[6:3] == 4'b1010 || id_funct7[6:3] == 4'b1100 || 
                                   (id_funct7[6:3] == 4'b1110 && id_funct3 == 3'b000) || 
                                   (id_funct7[6:3] == 4'b1110 && id_funct3 == 3'b001));

    // Integer register value used as the source for:
    // FCVT.fmt.int and FMV.fmt.X.
    wire gpr_to_fpu = id_is_fpu && (id_funct7[6:3] == 4'b1101 || 
                                   (id_funct7[6:3] == 4'b1111 && id_funct3 == 3'b000));
    
    // FPU operation decoder.
    always @(*) begin
        id_fpu_op = 4'd0;
        if (id_is_fpu) begin
            case (id_funct7[6:2])
                5'b00000: id_fpu_op = 4'd0; // FADD
                5'b00001: id_fpu_op = 4'd1; // FSUB
                5'b00010: id_fpu_op = 4'd2; // FMUL
                5'b00011: id_fpu_op = 4'd3; // FDIV
                5'b01011: id_fpu_op = 4'd4; // FSQRT
                5'b01000: id_fpu_op = 4'd6; // FCVT
                5'b11100: id_fpu_op = 4'd7; // FMV/FCLASS
                5'b11101: id_fpu_op = 4'd8; // MATH
                default:  id_fpu_op = 4'd0;
            endcase
        end
    end

    // Machine-level control instructions.
    wire id_is_mret = (id_opcode == 7'h73 && if_id_instr == 32'h30200073);
    wire id_is_wfi  = (id_opcode == 7'h73 && (if_id_instr == 32'h10500073 || if_id_instr == 32'h00100073));

    // Main instruction control decoder.
    always @(*) begin
        id_reg_we = 0; id_freg_we = 0; id_mem_we = 0; id_mem_re = 0;
        id_is_branch = 0; id_is_jump = 0; id_is_jalr = 0; id_is_auipc = 0; id_is_lui = 0;
        id_alu_ctrl = 5'b00000;
        
        case (id_opcode)

            // -----------------------------------------------------------------
            // U-TYPE AND CONTROL-FLOW INSTRUCTIONS
            // -----------------------------------------------------------------

            7'h37: begin id_is_lui = 1; id_reg_we = 1; end
            7'h17: begin id_is_auipc = 1; id_reg_we = 1; end
            7'h6F: begin id_is_jump = 1; id_reg_we = 1; end
            7'h67: begin id_is_jump = 1; id_is_jalr = 1; id_reg_we = 1; end
            7'h63: begin id_is_branch = 1; end

            // -----------------------------------------------------------------
            // INTEGER LOAD/STORE
            // -----------------------------------------------------------------

            7'h03: begin id_mem_re = 1; id_reg_we = 1; id_alu_ctrl = 5'b00000; end // Integer load
            7'h23: begin id_mem_we = 1; id_alu_ctrl = 5'b00000; end // Integer store
            
            // -----------------------------------------------------------------
            // FLOATING-POINT LOAD/STORE
            // -----------------------------------------------------------------

            7'h07: begin id_mem_re = 1; id_freg_we = 1; id_alu_ctrl = 5'b00000; end // FP load
            7'h27: begin id_mem_we = 1; id_alu_ctrl = 5'b00000; end // FP store
            
            // -----------------------------------------------------------------
            // FLOATING-POINT EXECUTION
            // -----------------------------------------------------------------

            // Route FPU results to either the GPR or FPR register file.
            7'h53: begin
                if (fpu_to_gpr) id_reg_we = 1;
                else id_freg_we = 1;
            end 
            
            // -----------------------------------------------------------------
            // OP-IMM
            // -----------------------------------------------------------------

            7'h13: begin 
                id_reg_we = 1;
                case (id_funct3)
                    3'b000: id_alu_ctrl = 5'b00000; 
                    3'b010: id_alu_ctrl = 5'b00011; 
                    3'b011: id_alu_ctrl = 5'b01001; 
                    3'b100: id_alu_ctrl = 5'b00100; 
                    3'b110: id_alu_ctrl = 5'b00110; 
                    3'b111: id_alu_ctrl = 5'b00111; 
                    3'b001: id_alu_ctrl = 5'b00010; 
                    3'b101: id_alu_ctrl = (id_funct7[5]) ? 5'b01000 : 5'b00101; 
                    default: id_alu_ctrl = 5'b00000;
                endcase
            end
            
            // -----------------------------------------------------------------
            // OP-IMM-32
            // -----------------------------------------------------------------

            7'h1B: begin 
                id_reg_we = 1;
                case (id_funct3)
                    3'b000: id_alu_ctrl = 5'b10000; 
                    3'b001: id_alu_ctrl = 5'b10010; 
                    3'b101: id_alu_ctrl = (id_funct7[5]) ? 5'b11000 : 5'b10101; 
                    default: id_alu_ctrl = 5'b10000;
                endcase
            end

            // -----------------------------------------------------------------
            // OP - REGISTER-REGISTER INTEGER OPERATIONS
            // -----------------------------------------------------------------

            7'h33: begin 
                id_reg_we = 1;
                if (!id_is_mdu) begin
                    case (id_funct3)
                        3'b000: id_alu_ctrl = (id_funct7[5]) ? 5'b00001 : 5'b00000; 
                        3'b001: id_alu_ctrl = 5'b00010; 
                        3'b010: id_alu_ctrl = 5'b00011; 
                        3'b100: id_alu_ctrl = 5'b00100; 
                        3'b101: id_alu_ctrl = (id_funct7[5]) ? 5'b01000 : 5'b00101; 
                        3'b110: id_alu_ctrl = 5'b00110; 
                        3'b111: id_alu_ctrl = 5'b00111; 
                        default: id_alu_ctrl = 5'b00000;
                    endcase
                end
            end
            
            // -----------------------------------------------------------------
            // OP-32 - REGISTER-REGISTER WORD OPERATIONS
            // -----------------------------------------------------------------

            7'h3B: begin 
                id_reg_we = 1;
                if (!id_is_mdu) begin
                    case (id_funct3)
                        3'b000: id_alu_ctrl = (id_funct7[5]) ? 5'b10001 : 5'b10000; 
                        3'b001: id_alu_ctrl = 5'b10010; 
                        3'b101: id_alu_ctrl = (id_funct7[5]) ? 5'b11000 : 5'b10101; 
                        default: id_alu_ctrl = 5'b10000;
                    endcase
                end
            end

        endcase
    end

    // Select the second ALU operand based on the instruction format.
    wire [63:0] id_alu_op2 = (id_opcode == 7'h33 || id_opcode == 7'h3B || id_is_branch) ? rf_read2 : 
                             (id_opcode == 7'h23 || id_opcode == 7'h27) ? id_imm_s : id_imm_i;

    // =========================================================================
    // ID/EX PIPELINE REGISTER
    // =========================================================================

    reg [63:0] id_ex_pc, id_ex_rdata1, id_ex_rdata2, id_ex_imm_b, id_ex_imm_j, id_ex_imm_u, id_ex_alu_op2;
    reg [63:0] id_ex_frdata1, id_ex_frdata2; 
    
    reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd, id_ex_alu_ctrl; 
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_opcode;
    
    reg id_ex_reg_we, id_ex_freg_we, id_ex_mem_we, id_ex_mem_re, id_ex_is_wfi; 
    reg id_ex_is_branch, id_ex_is_jump, id_ex_is_jalr, id_ex_is_auipc, id_ex_is_lui, id_ex_is_mret;
    
    reg        id_ex_is_mdu, id_ex_is_fpu;
    reg [3:0]  id_ex_mdu_op, id_ex_fpu_op;
    reg        id_ex_fpu_to_gpr, id_ex_gpr_to_fpu; 

    // ID/EX pipeline register update and flush logic.
    always @(posedge clk) begin
        if (!rstn || flush_id_ex) begin
            id_ex_reg_we <= 0; id_ex_freg_we <= 0; id_ex_mem_we <= 0; id_ex_mem_re <= 0;
            id_ex_is_branch <= 0; id_ex_is_jump <= 0; id_ex_is_mret <= 0;
            id_ex_rd <= 0; id_ex_is_wfi <= 0;
            id_ex_is_mdu <= 0; id_ex_is_fpu <= 0;
            id_ex_fpu_to_gpr <= 0; id_ex_gpr_to_fpu <= 0;
        end else if (!stall_ex && !cpu_halt) begin
            id_ex_pc        <= if_id_pc;
            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_rd        <= id_rd;
            
            id_ex_rdata1    <= rf_read1;   
            id_ex_rdata2    <= rf_read2;   
            id_ex_frdata1   <= frf_read1;  
            id_ex_frdata2   <= frf_read2;  
            
            id_ex_alu_op2   <= id_alu_op2;
            id_ex_imm_b     <= id_imm_b;
            id_ex_imm_j     <= id_imm_j;
            id_ex_imm_u     <= id_imm_u;
            id_ex_opcode    <= id_opcode;
            id_ex_alu_ctrl  <= id_alu_ctrl;
            id_ex_funct3    <= id_funct3;
            
            id_ex_reg_we    <= id_reg_we;
            id_ex_freg_we   <= id_freg_we;
            id_ex_mem_we    <= id_mem_we;
            id_ex_mem_re    <= id_mem_re;
            
            id_ex_is_branch <= id_is_branch;
            id_ex_is_jump   <= id_is_jump;
            id_ex_is_jalr   <= id_is_jalr;
            id_ex_is_auipc  <= id_is_auipc;
            id_ex_is_lui    <= id_is_lui;
            id_ex_is_mret   <= id_is_mret; 
            id_ex_is_wfi    <= id_is_wfi; 
            
            id_ex_is_mdu    <= id_is_mdu;
            id_ex_mdu_op    <= id_mdu_op;
            id_ex_is_fpu    <= id_is_fpu;  
            id_ex_fpu_op    <= id_fpu_op; 
            id_ex_fpu_to_gpr<= fpu_to_gpr; 
            id_ex_gpr_to_fpu<= gpr_to_fpu; 
        end
    end

    // Load-use hazard detection.
    // A stall is requested when a load in the EX stage writes to a register
    // required by the instruction currently being decoded.
    assign stall_load_use = (id_ex_mem_re && (id_ex_rd != 0) && (id_ex_rd == id_rs1 || id_ex_rd == id_rs2));

    // =========================================================================
    // EXECUTE (EX) AND DATA FORWARDING
    // =========================================================================

    reg [63:0] ex_mem_alu_res, ex_mem_fpu_res;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_we, ex_mem_freg_we, ex_mem_fpu_to_gpr;
    reg [2:0]  ex_mem_funct3;

    // -------------------------------------------------------------------------
    // INTEGER DATA FORWARDING
    // -------------------------------------------------------------------------

    // Forward from EX/MEM or MEM/WB when the destination register matches
    // the current EX-stage source register.
    wire [1:0] forward_a = (ex_mem_reg_we && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs1) ? 2'b10 :
                           (mem_wb_reg_we && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs1) ? 2'b01 : 2'b00;

    wire [1:0] forward_b = (ex_mem_reg_we && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs2) ? 2'b10 :
                           (mem_wb_reg_we && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs2) ? 2'b01 : 2'b00;

    wire [63:0] fwd_rs1_data = (forward_a == 2'b10) ? ex_mem_alu_res : (forward_a == 2'b01) ? wb_data : id_ex_rdata1;
    wire [63:0] fwd_rs2_data = (forward_b == 2'b10) ? ex_mem_alu_res : (forward_b == 2'b01) ? wb_data : id_ex_rdata2;

    // -------------------------------------------------------------------------
    // FLOATING-POINT DATA FORWARDING
    // -------------------------------------------------------------------------

    wire [1:0] forward_fa = (ex_mem_freg_we && ex_mem_rd == id_ex_rs1) ? 2'b10 :
                            (mem_wb_freg_we && mem_wb_rd == id_ex_rs1) ? 2'b01 : 2'b00;

    wire [1:0] forward_fb = (ex_mem_freg_we && ex_mem_rd == id_ex_rs2) ? 2'b10 :
                            (mem_wb_freg_we && mem_wb_rd == id_ex_rs2) ? 2'b01 : 2'b00;
                            
    wire [63:0] fwd_frs1_data = (forward_fa == 2'b10) ? ex_mem_fpu_res : (forward_fa == 2'b01) ? wb_fdata : id_ex_frdata1;
    wire [63:0] fwd_frs2_data = (forward_fb == 2'b10) ? ex_mem_fpu_res : (forward_fb == 2'b01) ? wb_fdata : id_ex_frdata2;

    // =========================================================================
    // ALU
    // =========================================================================

    // Select ALU source operands for AUIPC, jump, register, and immediate
    // instruction formats.
    wire [63:0] alu_src_a = (id_ex_is_auipc || id_ex_is_jump) ? id_ex_pc : fwd_rs1_data;
    wire [63:0] alu_src_b = (id_ex_is_auipc) ? id_ex_imm_u :
                            (id_ex_is_jump)  ? 64'd4 :
                            (id_ex_opcode == 7'h33 || id_ex_opcode == 7'h3B) ? fwd_rs2_data : id_ex_alu_op2; 

    wire [63:0] alu_result;
    wire alu_zero;

    vrm_alu_rv64i alu_inst (
        .src_a  (alu_src_a),
        .src_b  (alu_src_b),
        .ctrl   (id_ex_alu_ctrl),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // =========================================================================
    // INTEGER MULTIPLY/DIVIDE UNIT (MDU)
    // =========================================================================

    wire        mdu_busy, mdu_valid_out;
    wire [63:0] mdu_result_out;
    reg mdu_active;

    // Track active MDU operations.
    always @(posedge clk) begin
        if (!rstn || flush_ex) mdu_active <= 0;
        else if (id_ex_is_mdu && !mdu_active && !mdu_valid_out) mdu_active <= 1;
        else if (mdu_valid_out) mdu_active <= 0;
    end

    wire mdu_valid_in = id_ex_is_mdu && !mdu_active;

    // Hold the pipeline until the MDU produces a valid result.
    assign stall_mdu = id_ex_is_mdu && !mdu_valid_out;

    vrm_mdu_rv64m mdu_inst (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (mdu_valid_in),
        .op_a       (fwd_rs1_data),
        .op_b       (fwd_rs2_data),
        .mdu_op     (id_ex_mdu_op),
        .result_out (mdu_result_out),
        .valid_out  (mdu_valid_out),
        .busy       (mdu_busy)
    );

    // =========================================================================
    // FLOATING-POINT UNIT (FPU)
    // =========================================================================

    wire        fpu_valid_out;
    wire [63:0] fpu_result_out;
    reg fpu_active;

    // Track active FPU operations.
    always @(posedge clk) begin
        if (!rstn || flush_ex) fpu_active <= 0;
        else if (id_ex_is_fpu && !fpu_active && !fpu_valid_out) fpu_active <= 1;
        else if (fpu_valid_out) fpu_active <= 0;
    end
    
    wire fpu_valid_in = id_ex_is_fpu && !fpu_active;

    // Hold the pipeline until the FPU produces a valid result.
    assign stall_fpu = id_ex_is_fpu && !fpu_valid_out; 
    
    // Select the FPU operand source.
    // Integer GPR data is used for instructions that transfer or convert
    // integer values into the floating-point domain.
    wire [63:0] fpu_operand_a = id_ex_gpr_to_fpu ? fwd_rs1_data : fwd_frs1_data;

    vrm_fpu_rv64fd fpu_inst (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (fpu_valid_in),
        .fpu_op    (id_ex_fpu_op),
        .funct3    (id_ex_funct3),
        .op_a      (fpu_operand_a),
        .op_b      (fwd_frs2_data),
        .result_out(fpu_result_out),
        .valid_out (fpu_valid_out)
    );

    // Select the result produced by the active execution unit.
    wire [63:0] ex_stage_result = id_ex_is_mdu ? mdu_result_out : 
                                  id_ex_is_lui ? id_ex_imm_u : alu_result;

    wire [63:0] ex_stage_fresult = fpu_result_out;

    // =========================================================================
    // WRITE STROBE AND DATA ALIGNMENT
    // =========================================================================

    wire [2:0] store_offset = alu_result[2:0];

    // Select integer or floating-point store data based on the opcode.
    wire [63:0] raw_store_data = (id_ex_opcode == 7'h27) ? fwd_frs2_data : fwd_rs2_data;

    // Generate the base byte-write strobe from the store width.
    reg [7:0] base_wstrb;

    always @(*) begin
        if (id_ex_mem_we) begin
            case (id_ex_funct3)
                3'b000: base_wstrb = 8'b0000_0001; // SB / FSB
                3'b001: base_wstrb = 8'b0000_0011; // SH / FSH
                3'b010: base_wstrb = 8'b0000_1111; // SW / FSW
                3'b011: base_wstrb = 8'b1111_1111; // SD / FSD
                default: base_wstrb = 8'b0000_0000;
            endcase
        end else begin
            base_wstrb = 8'b0000_0000;
        end
    end

    // Shift the base write strobe according to the byte address offset.
    wire [7:0] aligned_wstrb = base_wstrb << store_offset;

    // Replicate narrow store data across the 64-bit memory data bus.
    wire [63:0] aligned_wdata;
    assign aligned_wdata = (id_ex_funct3 == 3'b010) ? {raw_store_data[31:0], raw_store_data[31:0]} : 
                           (id_ex_funct3 == 3'b001) ? {4{raw_store_data[15:0]}} : 
                           (id_ex_funct3 == 3'b000) ? {8{raw_store_data[7:0]}} : 
                           raw_store_data; 

    // =========================================================================
    // BRANCH AND JUMP LOGIC
    // =========================================================================

    wire is_eq  = (fwd_rs1_data == fwd_rs2_data);
    wire is_lt  = ($signed(fwd_rs1_data) < $signed(fwd_rs2_data));
    wire is_ltu = (fwd_rs1_data < fwd_rs2_data);

    reg branch_cond;

    // Evaluate branch condition according to funct3.
    always @(*) begin
        case (id_ex_funct3)
            3'b000: branch_cond = is_eq;   
            3'b001: branch_cond = !is_eq;  
            3'b100: branch_cond = is_lt;   
            3'b101: branch_cond = !is_lt;  
            3'b110: branch_cond = is_ltu;  
            3'b111: branch_cond = !is_ltu; 
            default: branch_cond = 0;
        endcase
    end

    // Control-flow instructions are taken only when the EX stage is not stalled.
    assign branch_taken_ex = ((id_ex_is_branch && branch_cond) || id_ex_is_jump) && !stall_ex;

    // Generate the target address for JALR, JAL, and conditional branches.
    assign target_pc_ex    = id_ex_is_jalr ? (fwd_rs1_data + id_ex_alu_op2) & 64'hFFFFFFFFFFFFFFFE : 
                             id_ex_is_jump ? (id_ex_pc + id_ex_imm_j) :                                      
                             (id_ex_pc + id_ex_imm_b);                                       

    // MRET returns execution to the saved machine exception program counter.
    assign is_mret_ex = id_ex_is_mret && !stall_ex;

    // Flush younger instructions after a taken control-flow operation.
    assign flush_ex   = branch_taken_ex || is_mret_ex;

    // =========================================================================
    // EX/MEM PIPELINE REGISTER
    // =========================================================================

    reg [7:0]  ex_mem_wstrb;
    reg [63:0] ex_mem_wdata;
    reg        ex_mem_mem_we, ex_mem_mem_re, ex_mem_is_wfi;

    always @(posedge clk) begin
        if (!rstn || irq_trigger) begin
            ex_mem_reg_we <= 0; ex_mem_freg_we <= 0; 
            ex_mem_mem_we <= 0; ex_mem_mem_re <= 0; 
            ex_mem_rd <= 0; ex_mem_is_wfi <= 0;
            ex_mem_fpu_to_gpr <= 0;
        end else if (!cpu_halt && !stall_ex) begin 
            ex_mem_alu_res <= ex_stage_result; 
            ex_mem_fpu_res <= ex_stage_fresult; 
            
            ex_mem_wdata   <= aligned_wdata; 
            ex_mem_wstrb   <= aligned_wstrb;
            
            ex_mem_rd      <= id_ex_rd;
            ex_mem_funct3  <= id_ex_funct3; 
            ex_mem_reg_we  <= id_ex_reg_we;
            ex_mem_freg_we <= id_ex_freg_we; 
            ex_mem_mem_we  <= id_ex_mem_we;
            ex_mem_mem_re  <= id_ex_mem_re;
            ex_mem_is_wfi  <= id_ex_is_wfi;
            ex_mem_fpu_to_gpr <= id_ex_fpu_to_gpr; 
        end
    end

    // =========================================================================
    // MEMORY ACCESS (MEM)
    // =========================================================================

    assign mem_addr  = ex_mem_alu_res;
    assign mem_wdata = ex_mem_wdata;
    assign mem_we    = ex_mem_mem_we;
    assign mem_wstrb = ex_mem_wstrb;
    
    // -------------------------------------------------------------------------
    // MEM/WB PIPELINE REGISTER
    // -------------------------------------------------------------------------

    reg [63:0] mem_wb_alu_res, mem_wb_fpu_res, mem_wb_mem_data;
    reg [2:0]  mem_wb_funct3;
    reg        mem_wb_mem_re, mem_wb_is_wfi, mem_wb_fpu_to_gpr;

    always @(posedge clk) begin
        if (!rstn || irq_trigger) begin
            mem_wb_reg_we <= 0; mem_wb_freg_we <= 0; 
            mem_wb_rd <= 0; mem_wb_is_wfi <= 0;
        end else if (!cpu_halt && !stall_mem) begin
            mem_wb_alu_res  <= ex_mem_alu_res;
            mem_wb_fpu_res  <= ex_mem_fpu_res; 
            mem_wb_mem_data <= mem_rdata; 
            mem_wb_rd       <= ex_mem_rd;
            mem_wb_funct3   <= ex_mem_funct3; 
            mem_wb_reg_we   <= ex_mem_reg_we;
            mem_wb_freg_we  <= ex_mem_freg_we; 
            mem_wb_mem_re   <= ex_mem_mem_re;
            mem_wb_is_wfi   <= mem_wb_is_wfi;
            mem_wb_fpu_to_gpr <= ex_mem_fpu_to_gpr; 
        end
    end

    // =========================================================================
    // WRITEBACK (WB) AND LOAD DATA EXTRACTION
    // =========================================================================

    reg [63:0] load_data_formatted;

    wire [2:0] load_byte_offset = mem_wb_alu_res[2:0];
    wire [63:0] mem_rdata_shifted = mem_wb_mem_data >> {load_byte_offset, 3'b000};

    // Extract and sign/zero extend loaded data according to funct3.
    always @(*) begin
        if (mem_wb_mem_re) begin
            case (mem_wb_funct3)
                3'b000: load_data_formatted = {{56{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0]};   // LB
                3'b001: load_data_formatted = {{48{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0]}; // LH
                3'b010: load_data_formatted = {{32{mem_rdata_shifted[31]}}, mem_rdata_shifted[31:0]}; // LW
                3'b011: load_data_formatted = mem_rdata_shifted;                                      // LD
                3'b100: load_data_formatted = {56'b0, mem_rdata_shifted[7:0]};                        // LBU
                3'b101: load_data_formatted = {48'b0, mem_rdata_shifted[15:0]};                       // LHU
                3'b110: load_data_formatted = {32'b0, mem_rdata_shifted[31:0]};                       // LWU
                default: load_data_formatted = mem_rdata_shifted;
            endcase
        end else begin
            load_data_formatted = 64'b0;
        end
    end

    // -------------------------------------------------------------------------
    // WRITEBACK DATA SELECTION
    // -------------------------------------------------------------------------

    always @(*) begin

        // Select the value written to the integer register file.
        wb_data = mem_wb_mem_re ? load_data_formatted : 
                  mem_wb_fpu_to_gpr ? mem_wb_fpu_res : 
                  mem_wb_alu_res;
        
        // NaN-box 32-bit floating-point load results into the 64-bit FPR.
        // FLW stores a single-precision value with all upper bits set to one.
        if (mem_wb_mem_re && mem_wb_funct3 == 3'b010) begin
            wb_fdata = {32'hFFFFFFFF, load_data_formatted[31:0]};
        end else begin
            wb_fdata = mem_wb_mem_re ? load_data_formatted : mem_wb_fpu_res; 
        end
    end

    // -------------------------------------------------------------------------
    // REGISTER FILE WRITE PORTS
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (mem_wb_reg_we && mem_wb_rd != 0) begin
            reg_file[mem_wb_rd] <= wb_data;
        end

        if (mem_wb_freg_we) begin
            freg_file[mem_wb_rd] <= wb_fdata;
        end
    end

    // =========================================================================
    // DEBUG AND HALT STATUS
    // =========================================================================

    assign debug_reg_x1 = reg_file[1];

    // Processor remains halted while WFI is active and no interrupt is pending.
    assign cpu_halt = mem_wb_is_wfi && !irq_trigger; 

endmodule
