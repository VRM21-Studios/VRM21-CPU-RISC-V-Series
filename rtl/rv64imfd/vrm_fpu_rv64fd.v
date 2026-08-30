`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

// ============================================================================
// Module      : vrm_fpu_rv64fd
// Description : 64-bit floating-point execution wrapper for the RV64 F and D
//               extensions.
//
// Functional Lanes:
//   Lane A    : Floating-point addition and subtraction
//   Lane B    : Floating-point multiplication
//   Lane C    : Floating-point division
//   Lane D    : Floating-point square root
//   Lane E    : Floating-point conversion
//   Lane F    : Floating-point miscellaneous operations
//   Lane MATH : Floating-point mathematical functions
//
// Interface:
// - valid_in  starts a floating-point operation.
// - fpu_op    selects the functional lane and operation category.
// - funct3    provides the operation-specific function field.
// - op_a      contains the first 64-bit operand.
// - op_b      contains the second 64-bit operand.
// - result_out contains the completed floating-point result.
// - valid_out indicates that result_out contains a valid result.
//
// Notes:
// - The wrapper uses an input register stage before dispatching operations to
//   the individual floating-point functional lanes.
// - Functional lanes operate independently and generate their own valid
//   signals.
// - Results from the functional lanes are selected using a priority
//   multiplexer and registered at the wrapper output.
// - The detailed operation encoding is defined by the FPU constants and
//   individual functional-lane implementations.
// - This module provides the floating-point execution interface used by the
//   RV64FD processor integration.
// ============================================================================

module vrm_fpu_rv64fd (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [3:0]  fpu_op,
    input  wire [2:0]  funct3,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,

    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // INPUT PIPELINE STAGE
    // =========================================================================
    // Captures the incoming operation and operands before dispatching them to
    // the corresponding floating-point functional lane.

    reg        s0_valid;
    reg [3:0]  s0_op;
    reg [2:0]  s0_f3;
    reg [63:0] s0_a;
    reg [63:0] s0_b;

    always @(posedge clk) begin

        if (!rstn) begin

            s0_valid <= 1'b0;
            s0_op    <= 4'd0;
            s0_f3    <= 3'd0;
            s0_a     <= 64'd0;
            s0_b     <= 64'd0;

        end else begin

            s0_valid <= valid_in;
            s0_op    <= fpu_op;
            s0_f3    <= funct3;
            s0_a     <= op_a;
            s0_b     <= op_b;

        end
    end

    // =========================================================================
    // FUNCTIONAL LANE ENABLE
    // =========================================================================
    // Each enable signal is asserted only when the input stage contains a
    // valid operation assigned to the corresponding functional lane.

    wire en_a = s0_valid && (s0_op == 4'd0 || s0_op == 4'd1);
    wire en_b = s0_valid && (s0_op == 4'd2);
    wire en_c = s0_valid && (s0_op == 4'd3);
    wire en_d = s0_valid && (s0_op == 4'd4);
    wire en_e = s0_valid && (s0_op == 4'd5 || s0_op == 4'd6);
    wire en_f = s0_valid && (s0_op == 4'd7);
    wire en_math = s0_valid && (s0_op == 4'd8);

    // =========================================================================
    // FUNCTIONAL LANE OUTPUTS
    // =========================================================================
    // Each functional lane provides a result and an associated valid signal.

    wire [63:0] res_a;
    wire [63:0] res_b;
    wire [63:0] res_c;
    wire [63:0] res_d;
    wire [63:0] res_e;
    wire [63:0] res_f;
    wire [63:0] res_math;

    wire vld_a;
    wire vld_b;
    wire vld_c;
    wire vld_d;
    wire vld_e;
    wire vld_f;
    wire vld_math;

    // =========================================================================
    // LANE A - ADDITION / SUBTRACTION
    // =========================================================================
    // Handles floating-point addition and subtraction operations.

    vrm_fpu_add_sub_64 lane_a (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_a),
        .is_sub     (s0_op[0]),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_a),
        .valid_out  (vld_a)
    );

    // =========================================================================
    // LANE B - MULTIPLICATION
    // =========================================================================
    // Handles floating-point multiplication operations.

    vrm_fpu_mul_64 lane_b (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_b),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_b),
        .valid_out  (vld_b)
    );

    // =========================================================================
    // LANE C - DIVISION
    // =========================================================================
    // Handles floating-point division operations.

    vrm_fpu_div_64 lane_c (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_c),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_c),
        .valid_out  (vld_c)
    );

    // =========================================================================
    // LANE D - SQUARE ROOT
    // =========================================================================
    // Handles floating-point square-root operations.

    vrm_fpu_sqrt_64 lane_d (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_d),
        .op_a       (s0_a),
        .result_out (res_d),
        .valid_out  (vld_d)
    );

    // =========================================================================
    // LANE E - CONVERSION
    // =========================================================================
    // Handles floating-point conversion operations.
    //
    // The conversion mode is derived from the selected FPU operation.

    wire [1:0] conv_mode =
        (s0_op == 4'd6) ? 2'b10 : 2'b00;

    vrm_fpu_conv_64 lane_e (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_e),
        .conv_op    (conv_mode),
        .op_a       (s0_a),
        .result_out (res_e),
        .valid_out  (vld_e)
    );

    // =========================================================================
    // LANE F - MISCELLANEOUS OPERATIONS
    // =========================================================================
    // Handles miscellaneous floating-point operations selected through
    // funct3.

    vrm_fpu_misc_64 lane_f (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_f),
        .misc_op    (s0_f3),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_f),
        .valid_out  (vld_f)
    );

    // =========================================================================
    // LANE MATH - MATHEMATICAL FUNCTIONS
    // =========================================================================
    // Handles additional floating-point mathematical functions selected
    // through funct3.

    vrm_fpu_math_64 lane_math (
        .clk        (clk),
        .rstn       (rstn),
        .func       (s0_f3),
        .valid_in   (en_math),
        .op_a       (s0_a),
        .result_out (res_math),
        .valid_out  (vld_math)
    );

    // =========================================================================
    // OUTPUT RESULT REGISTER
    // =========================================================================
    // Collects the valid result from the functional lanes.
    //
    // Lane priority:
    //   A > B > C > D > E > F > MATH
    //
    // The selected result and valid indication are registered at the output.

    always @(posedge clk) begin

        if (!rstn) begin

            valid_out  <= 1'b0;
            result_out <= 64'd0;

        end else begin

            valid_out <= vld_a  ||
                         vld_b  ||
                         vld_c  ||
                         vld_d  ||
                         vld_e  ||
                         vld_f  ||
                         vld_math;

            if (vld_a)
                result_out <= res_a;
            else if (vld_b)
                result_out <= res_b;
            else if (vld_c)
                result_out <= res_c;
            else if (vld_d)
                result_out <= res_d;
            else if (vld_e)
                result_out <= res_e;
            else if (vld_f)
                result_out <= res_f;
            else if (vld_math)
                result_out <= res_math;
            else
                result_out <= 64'd0;

        end
    end

endmodule
