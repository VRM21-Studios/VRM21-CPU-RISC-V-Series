`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_mdu_rv64m
// Description : Integer Multiplication and Division Unit implementing the
//               RISC-V M extension for the RV64 processor.
//
// Supported Operations:
//
// 64-bit Multiplication:
//   func3 = 3'b000 : MUL   - Lower XLEN bits of signed multiplication
//   func3 = 3'b001 : MULH  - Upper XLEN bits of signed × signed multiplication
//   func3 = 3'b010 : MULHSU - Upper XLEN bits of signed × unsigned multiplication
//   func3 = 3'b011 : MULHU - Upper XLEN bits of unsigned × unsigned multiplication
//
// 64-bit Division:
//   func3 = 3'b100 : DIV   - Signed division
//   func3 = 3'b101 : DIVU  - Unsigned division
//   func3 = 3'b110 : REM   - Signed remainder
//   func3 = 3'b111 : REMU  - Unsigned remainder
//
// 32-bit Word Operations:
//   mdu_op[3] = 1
//
//   func3 = 3'b000 : MULW  - 32-bit signed multiplication
//   func3 = 3'b100 : DIVW  - 32-bit signed division
//   func3 = 3'b101 : DIVUW - 32-bit unsigned division
//   func3 = 3'b110 : REMW  - 32-bit signed remainder
//   func3 = 3'b111 : REMUW - 32-bit unsigned remainder
//
// Interface:
// - valid_in  starts a multiplication or division operation.
// - op_a      contains the first source operand.
// - op_b      contains the second source operand.
// - mdu_op    selects the operation and word-operation mode.
// - result_out contains the completed operation result.
// - valid_out indicates that result_out contains a valid result.
// - busy      indicates that the divider is active or a division request
//             is currently being accepted.
//
// Notes:
// - The multiplier path is combinational and provides a one-cycle result
//   through the sequential output interface.
// - The multiplier is explicitly marked for DSP inference.
// - Normal division uses an iterative radix-2 unsigned division algorithm.
// - Divide-by-zero and signed overflow conditions use a one-cycle fast path.
// - Word operations operate on the lower 32 bits and produce sign-extended
//   64-bit results.
// - The implementation is written using Verilog-2001-compatible constructs.
// ============================================================================

module vrm_mdu_rv64m (
    input  wire        clk,
    input  wire        rstn,

    input  wire        valid_in,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,
    input  wire [3:0]  mdu_op,

    output reg  [63:0] result_out,
    output reg         valid_out,
    output wire        busy
);

    // =========================================================================
    // OPERATION DECODING
    // =========================================================================
    // mdu_op[3] selects 32-bit word operations.
    // mdu_op[2:0] contains the RISC-V funct3 operation field.

    wire       is_word_op = mdu_op[3];
    wire [2:0] func3      = mdu_op[2:0];

    wire is_mul = (func3 == 3'b000 || func3 == 3'b001 ||
                   func3 == 3'b010 || func3 == 3'b011);

    wire is_div = (func3 == 3'b100 || func3 == 3'b101 ||
                   func3 == 3'b110 || func3 == 3'b111);

    // Signed interpretation of operand A.
    wire is_signed_a = (func3 == 3'b001 || func3 == 3'b010 ||
                        func3 == 3'b100 || func3 == 3'b110);

    // Signed interpretation of operand B.
    wire is_signed_b = (func3 == 3'b001 || func3 == 3'b100 ||
                        func3 == 3'b110);

    // =========================================================================
    // MULTIPLIER PATH
    // =========================================================================
    // Operands are extended to 65 bits so that signed and unsigned
    // multiplication modes can be represented explicitly.
    //
    // Word operations use the lower 32 bits and apply the corresponding
    // sign interpretation before multiplication.

    wire signed [64:0] mul_a = {
        (is_signed_a & (is_word_op ? op_a[31] : op_a[63])),
        (is_word_op ? {32'b0, op_a[31:0]} : op_a)
    };

    wire signed [64:0] mul_b = {
        (is_signed_b & (is_word_op ? op_b[31] : op_b[63])),
        (is_word_op ? {32'b0, op_b[31:0]} : op_b)
    };

    // Request DSP-based implementation where supported by the target FPGA.

    (* use_dsp = "yes" *) wire signed [129:0] mul_result_full = mul_a * mul_b;

    // Final multiplier result before being registered into result_out.

    reg [63:0] mul_final_res;

    always @(*) begin

        if (is_word_op) begin

            // =================================================================
            // WORD MULTIPLICATION
            // =================================================================
            // Word multiplication produces a 32-bit result that is sign-extended
            // to the 64-bit destination width.

            mul_final_res = {{32{mul_result_full[31]}}, mul_result_full[31:0]};

        end else begin

            // =================================================================
            // 64-BIT MULTIPLICATION
            // =================================================================

            case (func3)

                // -----------------------------------------------------------------
                // MUL - Lower 64 Bits
                // -----------------------------------------------------------------
                3'b000:
                    mul_final_res = mul_result_full[63:0];

                // -----------------------------------------------------------------
                // MULH - Upper 64 Bits, Signed × Signed
                // -----------------------------------------------------------------
                3'b001:
                    mul_final_res = mul_result_full[127:64];

                // -----------------------------------------------------------------
                // MULHSU - Upper 64 Bits, Signed × Unsigned
                // -----------------------------------------------------------------
                3'b010:
                    mul_final_res = mul_result_full[127:64];

                // -----------------------------------------------------------------
                // MULHU - Upper 64 Bits, Unsigned × Unsigned
                // -----------------------------------------------------------------
                3'b011:
                    mul_final_res = mul_result_full[127:64];

                // -----------------------------------------------------------------
                // DEFAULT
                // -----------------------------------------------------------------
                default:
                    mul_final_res = 64'd0;

            endcase
        end
    end

    // =========================================================================
    // DIVISION EDGE-CASE DETECTION
    // =========================================================================
    // Detects conditions defined by the RISC-V M extension that do not require
    // iterative division:
    //
    // - Division or remainder by zero.
    // - Signed division overflow for the minimum signed value divided by -1.

    wire [63:0] op_a_prep =
        is_word_op ? {{32{is_signed_a & op_a[31]}}, op_a[31:0]} : op_a;

    wire [63:0] op_b_prep =
        is_word_op ? {{32{is_signed_b & op_b[31]}}, op_b[31:0]} : op_b;

    wire is_zero_b = (op_b_prep == 64'd0);

    wire is_rem_op = (func3 == 3'b110 || func3 == 3'b111);

    // Signed overflow condition for XLEN = 64:
    //
    //   -2^63 / -1

    wire is_ovf_64 =
        (op_a == 64'h8000_0000_0000_0000) &&
        (op_b == 64'hFFFF_FFFF_FFFF_FFFF);

    // Signed overflow condition for XLEN = 32:
    //
    //   -2^31 / -1

    wire is_ovf_32 =
        (op_a[31:0] == 32'h8000_0000) &&
        (op_b[31:0] == 32'hFFFF_FFFF);

    wire is_ovf =
        (is_signed_a && is_signed_b) &&
        (is_word_op ? is_ovf_32 : is_ovf_64);

    // =========================================================================
    // ITERATIVE DIVIDER
    // =========================================================================
    // Normal division is performed using an iterative radix-2 unsigned
    // division algorithm. Signed operands are converted to their absolute
    // values before entering the iterative divider.

    localparam ST_IDLE     = 2'd0,
               ST_DIVIDING = 2'd1,
               ST_DONE     = 2'd2;

    reg [1:0]   div_state;
    reg [6:0]   div_count;
    reg [127:0] div_rq;
    reg [63:0]  div_b;

    reg div_sign_q;
    reg div_sign_r;
    reg div_is_rem_reg;
    reg div_is_word_reg;

    // Operand sign detection.

    wire a_is_neg = is_signed_a & op_a_prep[63];
    wire b_is_neg = is_signed_b & op_b_prep[63];

    // Absolute values used by the unsigned iterative divider.

    wire [63:0] abs_a =
        a_is_neg ? (~op_a_prep + 64'd1) : op_a_prep;

    wire [63:0] abs_b =
        b_is_neg ? (~op_b_prep + 64'd1) : op_b_prep;

    // Divider is busy while an operation is being processed or when a new
    // division request is currently being accepted.

    assign busy = (div_state != ST_IDLE) || (valid_in && is_div);

    // =========================================================================
    // DIVISION RESULT SIGN FINALIZATION
    // =========================================================================
    // The iterative divider operates on absolute values. The quotient and
    // remainder signs are restored after the iterative operation completes.

    wire [63:0] final_q =
        div_sign_q ? (~div_rq[63:0] + 64'd1) : div_rq[63:0];

    wire [63:0] final_r =
        div_sign_r ? (~div_rq[127:64] + 64'd1) : div_rq[127:64];

    // =========================================================================
    // DIVIDER FSM CONTROL
    // =========================================================================

    always @(posedge clk) begin

        if (!rstn) begin

            div_state  <= ST_IDLE;
            valid_out  <= 0;
            result_out <= 0;

        end else begin

            case (div_state)

                // =================================================================
                // IDLE
                // =================================================================
                ST_IDLE: begin

                    valid_out <= 0;

                    if (valid_in) begin

                        if (is_mul) begin

                            // -----------------------------------------------------
                            // FAST PATH: MULTIPLIER
                            // -----------------------------------------------------
                            // The multiplier result is available directly from
                            // the combinational multiplier path.

                            result_out <= mul_final_res;
                            valid_out  <= 1;

                        end else if (is_div) begin

                            if (is_zero_b) begin

                                // -------------------------------------------------
                                // FAST PATH: DIVISION BY ZERO
                                // -------------------------------------------------

                                if (is_word_op)
                                    result_out <= is_rem_op ?
                                                  {{32{op_a_prep[31]}},
                                                   op_a_prep[31:0]} :
                                                  64'hFFFFFFFFFFFFFFFF;
                                else
                                    result_out <= is_rem_op ?
                                                  op_a_prep :
                                                  64'hFFFFFFFFFFFFFFFF;

                                valid_out <= 1;

                            end else if (is_ovf) begin

                                // -------------------------------------------------
                                // FAST PATH: SIGNED DIVISION OVERFLOW
                                // -------------------------------------------------

                                if (is_word_op)
                                    result_out <= is_rem_op ?
                                                  64'd0 :
                                                  {{32{1'b1}},
                                                   32'h8000_0000};
                                else
                                    result_out <= is_rem_op ?
                                                  64'd0 :
                                                  64'h8000_0000_0000_0000;

                                valid_out <= 1;

                            end else begin

                                // -------------------------------------------------
                                // SLOW PATH: ITERATIVE DIVISION
                                // -------------------------------------------------

                                div_b           <= abs_b;
                                div_rq          <= {64'd0, abs_a};
                                div_count       <= is_word_op ? 7'd32 : 7'd64;
                                div_sign_q      <= a_is_neg ^ b_is_neg;
                                div_sign_r      <= a_is_neg;
                                div_is_rem_reg  <= is_rem_op;
                                div_is_word_reg <= is_word_op;
                                div_state       <= ST_DIVIDING;

                            end
                        end
                    end
                end

                // =================================================================
                // DIVIDING
                // =================================================================
                ST_DIVIDING: begin

                    if (div_count == 0) begin

                        div_state <= ST_DONE;

                    end else begin

                        div_count <= div_count - 1;

                        if (div_rq[126:63] >= div_b) begin

                            div_rq <= {
                                (div_rq[126:63] - div_b),
                                div_rq[62:0],
                                1'b1
                            };

                        end else begin

                            div_rq <= {
                                div_rq[126:0],
                                1'b0
                            };

                        end
                    end
                end

                // =================================================================
                // DONE
                // =================================================================
                ST_DONE: begin

                    if (div_is_word_reg) begin

                        result_out <= div_is_rem_reg ?
                                      {{32{final_r[31]}}, final_r[31:0]} :
                                      {{32{final_q[31]}}, final_q[31:0]};

                    end else begin

                        result_out <= div_is_rem_reg ?
                                      final_r :
                                      final_q;
                    end

                    valid_out <= 1;
                    div_state <= ST_IDLE;

                end

            endcase
        end
    end

endmodule
