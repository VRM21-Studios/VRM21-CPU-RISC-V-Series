`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_mdu
// DESCRIPTION : RV32M multiply/divide unit for the RV32IM core.
//
// Features:
//   - MUL, MULH, MULHSU, MULHU: combinational 64-bit products, result
//     registered one cycle after start.
//   - DIV, DIVU, REM, REMU: restoring division over 32 iterations, operating
//     on magnitudes with the sign applied at the end.
//   - Division by zero and signed overflow return the values defined by the
//     RISC-V M extension without iterating.
//
// Interface:
//   start pulses with op (= funct3) and operands; done pulses for one cycle
//   with result; busy is high while a division iterates.
//
// Notes:
//   - The combinational multiplier is the critical setup path of the SoC
//     at 100 MHz on the Kria KR260 (implementation WNS +0.644 ns, forwarded
//     operand into the DSP product).
// ============================================================================
module vrm_mdu (
    input  wire        clk,
    input  wire        rstn,

    input  wire        start,
    input  wire [2:0]  op,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,

    output reg  [31:0] result,
    output reg         done,
    output wire        busy
);

    wire is_mul = (op[2:0] <= 3'b011);

    // ========================================================================
    // 1. MULTIPLIER (combinational 64-bit)
    // ========================================================================
    wire signed [63:0] a_s = {{32{src_a[31]}}, src_a};
    wire signed [63:0] b_s = {{32{src_b[31]}}, src_b};
    wire        [63:0] a_u = {32'b0, src_a};
    wire        [63:0] b_u = {32'b0, src_b};

    wire signed [63:0] prod_ss = a_s * b_s;
    wire signed [63:0] prod_su = a_s * b_u;
    wire        [63:0] prod_uu = a_u * b_u;

    reg [31:0] mul_result;
    always @(*) begin
        case (op[2:0])
            3'b000: mul_result = prod_ss[31:0];   // MUL
            3'b001: mul_result = prod_ss[63:32];  // MULH
            3'b010: mul_result = prod_su[63:32];  // MULHSU
            3'b011: mul_result = prod_uu[63:32];  // MULHU
            default: mul_result = 32'b0;
        endcase
    end

    // ========================================================================
    // 2. DIVIDER (restoring division, 32 iterations)
    //   div_shift = {remainder[31:0], quotient[31:0]}
    //   Each iteration shifts left by one, moves the quotient MSB into the
    //   remainder LSB, subtracts the divisor when the remainder is large
    //   enough, and sets the new quotient LSB.
    // ========================================================================
    localparam DIV_IDLE = 1'b0;
    localparam DIV_RUN  = 1'b1;

    reg         div_state;
    reg  [5:0]  div_count;
    reg  [63:0] div_shift;
    reg  [31:0] div_dvsr;
    reg         div_sign_q;
    reg         div_sign_r;
    reg         div_is_rem;

    wire [31:0] abs_a = src_a[31] ? (~src_a + 1'b1) : src_a;
    wire [31:0] abs_b = src_b[31] ? (~src_b + 1'b1) : src_b;

    wire div_by_zero = (src_b == 32'b0);
    wire div_ovf_q   = (src_a == 32'h8000_0000) && (src_b == 32'hFFFF_FFFF);

    assign busy = (div_state == DIV_RUN);

    // ------------------------------------------------------------------------
    // Divider next iteration (combinational)
    // ------------------------------------------------------------------------
    wire [63:0] shifted    = {div_shift[62:0], 1'b0};
    wire        sub_en     = (shifted[63:32] >= div_dvsr);
    wire [31:0] rem_next   = sub_en ? (shifted[63:32] - div_dvsr)
                                    :  shifted[63:32];
    wire [31:0] quo_next   = sub_en ? {shifted[31:1], 1'b1}
                                    :  shifted[31:0];
    wire [63:0] shift_next = {rem_next, quo_next};

    // ========================================================================
    // 3. CONTROL FSM
    //   DIV_IDLE : accept start; multiply and special-case divides finish here
    //   DIV_RUN  : iterate until div_count reaches 1, then apply the sign
    // ========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            div_state  <= DIV_IDLE;
            div_count  <= 6'd0;
            div_shift  <= 64'd0;
            div_dvsr   <= 32'd0;
            div_sign_q <= 1'b0;
            div_sign_r <= 1'b0;
            div_is_rem <= 1'b0;
            result     <= 32'd0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            case (div_state)
                // ----------------------------------------------------------
                DIV_IDLE: begin
                    if (start) begin
                        if (is_mul) begin
                            result <= mul_result;
                            done   <= 1'b1;
                        end else begin
                            if (div_by_zero) begin
                                if (op[2:0] == 3'b110 || op[2:0] == 3'b111)
                                    result <= src_a;            // REM/REMU: dividend
                                else
                                    result <= 32'hFFFF_FFFF;    // DIV/DIVU: -1
                                done <= 1'b1;
                            end
                            else if (div_ovf_q && op[2:0] == 3'b100) begin
                                result <= 32'h8000_0000;        // DIV overflow
                                done   <= 1'b1;
                            end
                            else if (div_ovf_q && op[2:0] == 3'b110) begin
                                result <= 32'b0;                // REM overflow
                                done   <= 1'b1;
                            end
                            else begin
                                div_is_rem <= (op[2:0] == 3'b110) ||
                                              (op[2:0] == 3'b111);

                                if (op[2:0] == 3'b100 || op[2:0] == 3'b110) begin
                                    // signed
                                    div_sign_q <= src_a[31] ^ src_b[31];
                                    div_sign_r <= src_a[31];
                                    div_shift  <= {32'b0, abs_a};
                                    div_dvsr   <= abs_b;
                                end else begin
                                    // unsigned
                                    div_sign_q <= 1'b0;
                                    div_sign_r <= 1'b0;
                                    div_shift  <= {32'b0, src_a};
                                    div_dvsr   <= src_b;
                                end
                                div_count <= 6'd32;
                                div_state <= DIV_RUN;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                DIV_RUN: begin
                    div_shift <= shift_next;
                    div_count <= div_count - 1'b1;

                    if (div_count == 6'd1) begin
                        if (div_is_rem)
                            result <= div_sign_r ? (~rem_next + 1'b1)
                                                 :  rem_next;
                        else
                            result <= div_sign_q ? (~quo_next + 1'b1)
                                                 :  quo_next;
                        done      <= 1'b1;
                        div_state <= DIV_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
