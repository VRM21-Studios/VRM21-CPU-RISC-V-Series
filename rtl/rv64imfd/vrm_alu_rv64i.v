`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_alu_rv64i
// Description : 64-bit combinational Arithmetic Logic Unit used by the
//               VRM RV64I processor core.
//
// Supported Operations:
//
// Full 64-bit Operations:
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
// 32-bit Word Operations:
//   ctrl[4] = 1
//
//   4'b0000 : ADDW - 32-bit addition with sign extension
//   4'b0001 : SUBW - 32-bit subtraction with sign extension
//   4'b0010 : SLLW - 32-bit logical left shift with sign extension
//   4'b0101 : SRLW - 32-bit logical right shift with sign extension
//   4'b1000 : SRAW - 32-bit arithmetic right shift with sign extension
//
// Output:
// - result contains the selected ALU operation result.
// - zero is asserted when result is equal to zero.
//
// Notes:
// - The ALU is purely combinational.
// - ctrl[4] selects between full 64-bit operations and 32-bit word
//   operations.
// - Full 64-bit shift amounts are taken from src_b[5:0], supporting shifts
//   from 0 to 63 bits.
// - Word-operation shift amounts are taken from b32[4:0], supporting shifts
//   from 0 to 31 bits.
// - Word-operation results are sign-extended from 32 bits to 64 bits.
// - Signed interpretation is applied only to operations that explicitly
//   require signed arithmetic.
// - The implementation uses intermediate 32-bit storage for word operations
//   to maintain Verilog-2001 compatibility.
// ============================================================================

module vrm_alu_rv64i (
    input  [63:0] src_a,
    input  [63:0] src_b,
    input  [4:0]  ctrl,

    output reg [63:0] result,
    output            zero
);

    // =========================================================================
    // OPERATION MODE SELECTION
    // =========================================================================
    // ctrl[4] selects 32-bit word operations.
    // ctrl[3:0] selects the specific ALU operation.

    wire       is_word_op = ctrl[4];
    wire [3:0] op          = ctrl[3:0];

    // =========================================================================
    // 32-BIT OPERANDS
    // =========================================================================
    // Lower 32 bits of the source operands are used by RV64 word operations.

    wire [31:0] a32 = src_a[31:0];
    wire [31:0] b32 = src_b[31:0];

    // Intermediate register used to store the 32-bit word-operation result
    // before sign-extension to the 64-bit ALU output.

    reg [31:0] res32;

    // =========================================================================
    // ALU OPERATION SELECTION
    // =========================================================================

    always @(*) begin

        if (is_word_op) begin

            // =================================================================
            // 32-BIT WORD OPERATIONS
            // =================================================================

            case (op)

                // -----------------------------------------------------------------
                // ADDW - Add Word
                // -----------------------------------------------------------------
                4'b0000:
                    res32 = a32 + b32;

                // -----------------------------------------------------------------
                // SUBW - Subtract Word
                // -----------------------------------------------------------------
                4'b0001:
                    res32 = a32 - b32;

                // -----------------------------------------------------------------
                // SLLW - Shift Left Logical Word
                // -----------------------------------------------------------------
                4'b0010:
                    res32 = a32 << b32[4:0];

                // -----------------------------------------------------------------
                // SRLW - Shift Right Logical Word
                // -----------------------------------------------------------------
                4'b0101:
                    res32 = a32 >> b32[4:0];

                // -----------------------------------------------------------------
                // SRAW - Shift Right Arithmetic Word
                // -----------------------------------------------------------------
                4'b1000:
                    res32 = $signed(a32) >>> b32[4:0];

                // -----------------------------------------------------------------
                // DEFAULT
                // -----------------------------------------------------------------
                // Unsupported or undefined word-operation codes produce zero.
                default:
                    res32 = 32'b0;

            endcase

            // =================================================================
            // WORD RESULT SIGN EXTENSION
            // =================================================================
            // RV64 word operations produce a 32-bit result that is sign-extended
            // to the full 64-bit destination width.

            result = {{32{res32[31]}}, res32};

        end else begin

            // =================================================================
            // 64-BIT OPERATIONS
            // =================================================================

            case (op)

                // -----------------------------------------------------------------
                // ADD - Add
                // -----------------------------------------------------------------
                4'b0000:
                    result = src_a + src_b;

                // -----------------------------------------------------------------
                // SUB - Subtract
                // -----------------------------------------------------------------
                4'b0001:
                    result = src_a - src_b;

                // -----------------------------------------------------------------
                // SLL - Shift Left Logical
                // -----------------------------------------------------------------
                4'b0010:
                    result = src_a << src_b[5:0];

                // -----------------------------------------------------------------
                // SLT - Set Less Than, Signed
                // -----------------------------------------------------------------
                4'b0011:
                    result = ($signed(src_a) < $signed(src_b)) ? 64'd1 : 64'd0;

                // -----------------------------------------------------------------
                // XOR
                // -----------------------------------------------------------------
                4'b0100:
                    result = src_a ^ src_b;

                // -----------------------------------------------------------------
                // SRL - Shift Right Logical
                // -----------------------------------------------------------------
                4'b0101:
                    result = src_a >> src_b[5:0];

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
                    result = $signed(src_a) >>> src_b[5:0];

                // -----------------------------------------------------------------
                // DEFAULT
                // -----------------------------------------------------------------
                // Unsupported or undefined operation codes produce zero.
                default:
                    result = 64'b0;

            endcase

        end
    end

    // =========================================================================
    // ZERO FLAG
    // =========================================================================
    // Asserted whenever the ALU result is equal to zero.

    assign zero = (result == 64'b0);

endmodule
