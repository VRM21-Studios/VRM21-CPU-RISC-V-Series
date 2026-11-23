`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_alu
// DESCRIPTION : Combinational integer ALU for the RV32IM core (RV32I base
//               operations only; multiply and divide live in vrm_mdu).
//
// Features:
//   - ADD, SUB, SLL, SLT, SLTU, XOR, SRL, OR, AND, SRA selected by ctrl.
//   - Shift amounts use src_b[4:0], as required by RV32I.
//
// Notes:
//   - zero is derived from the result and is not used for branch decisions
//     in the core, which compares operands directly.
// ============================================================================

module vrm_alu(
    input  [31:0] src_a, src_b,
    input  [3:0]  ctrl,
    output reg [31:0] result,
    output zero
);
    always @(*) begin
        case (ctrl)
            4'b0000: result = src_a + src_b; // ADD
            4'b0001: result = src_a - src_b; // SUB
            4'b0010: result = src_a << src_b[4:0]; // SLL
            4'b0011: result = ($signed(src_a) < $signed(src_b)) ? 1 : 0; // SLT (signed)
            4'b1010: result = (src_a < src_b) ? 1 : 0; // SLTU (unsigned)
            4'b0100: result = src_a ^ src_b; // XOR
            4'b0101: result = src_a >> src_b[4:0]; // SRL (logical)
            4'b0110: result = src_a | src_b; // OR
            4'b0111: result = src_a & src_b; // AND
            4'b1000: result = $signed(src_a) >>> src_b[4:0]; // SRA (arithmetic)
            default: result = 0;
        endcase
    end
    assign zero = (result == 0);
endmodule
