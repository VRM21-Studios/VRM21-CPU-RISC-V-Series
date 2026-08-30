`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_alu
// Description : 32-bit combinational Arithmetic Logic Unit used by the
//               VRM RISC-V processor core.
//
// Supported Operations:
//   4'b0000 : ADD - Addition
//   4'b0001 : SUB - Subtraction
//   4'b0010 : SLL - Logical left shift
//   4'b0011 : SLT - Signed set-less-than comparison
//   4'b0100 : XOR - Bitwise XOR
//   4'b0101 : SRL - Logical right shift
//   4'b0110 : OR  - Bitwise OR
//   4'b0111 : AND - Bitwise AND
//   4'b1000 : SRA - Arithmetic right shift
//
// Output:
// - result contains the selected ALU operation result.
// - zero is asserted when result is equal to zero.
//
// Notes:
// - The ALU is purely combinational.
// - Shift amount is taken from src_b[4:0], supporting shifts from 0 to 31 bits.
// - Signed interpretation is applied only to operations that explicitly
//   require signed arithmetic.
// ============================================================================

module vrm_alu (
    input  [31:0] src_a,
    input  [31:0] src_b,
    input  [3:0]  ctrl,

    output reg [31:0] result,
    output            zero
);

    // =========================================================================
    // ALU OPERATION SELECTION
    // =========================================================================

    always @(*) begin

        case (ctrl)

            // -----------------------------------------------------------------
            // ADD
            // -----------------------------------------------------------------
            4'b0000:
                result = src_a + src_b;

            // -----------------------------------------------------------------
            // SUB
            // -----------------------------------------------------------------
            4'b0001:
                result = src_a - src_b;

            // -----------------------------------------------------------------
            // SLL - Shift Left Logical
            // -----------------------------------------------------------------
            4'b0010:
                result = src_a << src_b[4:0];

            // -----------------------------------------------------------------
            // SLT - Set Less Than, Signed
            // -----------------------------------------------------------------
            4'b0011:
                result = ($signed(src_a) < $signed(src_b)) ? 1 : 0;

            // -----------------------------------------------------------------
            // XOR
            // -----------------------------------------------------------------
            4'b0100:
                result = src_a ^ src_b;

            // -----------------------------------------------------------------
            // SRL - Shift Right Logical
            // -----------------------------------------------------------------
            4'b0101:
                result = src_a >> src_b[4:0];

            // -----------------------------------------------------------------
            // OR
            // -----------------------------------------------------------------
            4'b0110:
                result = src_a | src_b;

            // -----------------------------------------------------------------
            // AND
            // -----------------------------------------------------------------
            4'b0111:
                result = src_a & src_b;

            // -----------------------------------------------------------------
            // SRA - Shift Right Arithmetic
            // -----------------------------------------------------------------
            4'b1000:
                result = $signed(src_a) >>> src_b[4:0];

            // -----------------------------------------------------------------
            // DEFAULT
            // -----------------------------------------------------------------
            // Unsupported or undefined operation codes produce zero.
            default:
                result = 0;

        endcase
    end

    // =========================================================================
    // ZERO FLAG
    // =========================================================================
    // Asserted whenever the ALU result is equal to zero.
    assign zero = (result == 0);

endmodule
