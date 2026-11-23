`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_vcf_core
// DESCRIPTION : One channel of a Chamberlin state-variable filter (SVF) with
//               low-pass, high-pass, and band-pass outputs, limit-cycle
//               suppression, and atomic parameter commit at a zero crossing.
//
// Features:
//   - Per sample: hp = x - lp - q*bp; bp = bp + f*hp; lp = lp + f*bp.
//   - Parameters are taken from shadow inputs and copied to the active set
//     only when commit_req is high, a zero crossing has been seen, and the
//     FSM is idle (sample boundary). commit_ack pulses for one cycle.
//   - A zero crossing is a sign change against the previous input sample or
//     an input sample equal to 0, so a muted source (all zeros) still lets
//     parameters commit.
//   - Limit-cycle suppression: when the input is 0 and |lp|, |bp|, |hp| are
//     all below LCO, the filter state is cleared to 0.
//
// Fixed-point format:
//   - audio_in, lp/hp/bp state and outputs: signed Q1.15.
//   - cutoff (f) and resonance (q): signed Q1.15 coefficients.
//   - Products are signed 32-bit (Q2.30); each is rounded by adding 2^14 and
//     shifting right by 15, then saturated to 16 bits (sat_16b).
//   - lco: unsigned magnitude threshold in Q1.15 LSBs.
//
// Notes:
//   - The FSM processes one sample at a time, starting when en is high in
//     S_IDLE; valid_out pulses when lp/hp/bp outputs are updated.
//   - S_Q_MULT is declared but not used by the FSM.
//   - Algorithm: H. Chamberlin, "Musical Applications of Microprocessors".
// ============================================================================

module vrm_vcf_core (
    input  wire                  clk,
    input  wire                  rstn,
    input  wire                  en,

    // Audio input
    input  wire signed [15:0]    audio_in,

    // Shadow parameter inputs (not active until commit)
    input  wire signed [15:0]    cutoff_shadow,
    input  wire signed [15:0]    res_shadow,
    input  wire [15:0]           lco_shadow,
    input  wire [1:0]            ftype_shadow,
    input  wire                  commit_req,   // level: 1 = armed

    // Outputs
    output reg  signed [15:0]    lp_out,
    output reg  signed [15:0]    hp_out,
    output reg  signed [15:0]    bp_out,
    output reg  [1:0]            ftype_active, // committed filter type for the output mux
    output reg                   commit_ack,   // one-cycle pulse on an actual commit
    output reg                   valid_out
);

    // ==========================================
    // 1. ACTIVE (LATCHED) PARAMETERS
    // ==========================================
    reg signed [15:0] active_cutoff;
    reg signed [15:0] active_res;
    reg [15:0]        active_lco;

    // ==========================================
    // 2. FSM STATE (declared early for commit gating)
    // ==========================================
    localparam S_IDLE    = 3'd0;
    localparam S_Q_MULT  = 3'd1;
    localparam S_HP_CALC = 3'd2;
    localparam S_F1_MULT = 3'd3;
    localparam S_BP_CALC = 3'd4;
    localparam S_F2_MULT = 3'd5;
    localparam S_LP_CALC = 3'd6;

    reg [2:0] state;
    wire fsm_idle = (state == S_IDLE);

    // ==========================================
    // 3. ZERO-CROSSING DETECTION
    // ==========================================
    //  Sign change, or an input sample of exactly 0.
    // ==========================================
    reg  prev_sign;
    reg  zcd_pending;   // crossing seen since the last commit

    wire sign_now = audio_in[15];
    wire zcd_raw  = (sign_now != prev_sign) || (audio_in == 16'd0);

    // ==========================================
    // 4. COMMIT CONTROLLER
    // ==========================================
    //   - Crossings are tracked while en = 1.
    //   - A commit happens only while the FSM is idle, so all parameters
    //     change together between two samples.
    // ==========================================
    always @(posedge clk) begin
        if (!rstn) begin
            prev_sign     <= 1'b0;
            zcd_pending   <= 1'b0;
            active_cutoff <= cutoff_shadow;
            active_res    <= res_shadow;
            active_lco    <= lco_shadow;
            ftype_active  <= ftype_shadow;
            commit_ack    <= 1'b0;
        end else begin
            commit_ack <= 1'b0;

            if (en) begin
                prev_sign <= sign_now;
                if (zcd_raw) zcd_pending <= 1'b1;
            end

            if (commit_req && zcd_pending && fsm_idle) begin
                active_cutoff <= cutoff_shadow;
                active_res    <= res_shadow;
                active_lco    <= lco_shadow;
                ftype_active  <= ftype_shadow;
                zcd_pending   <= 1'b0;
                commit_ack    <= 1'b1;
            end
        end
    end

    // ==========================================
    // 5. UTILITY FUNCTIONS
    // ==========================================
    function signed [15:0] sat_16b(input signed [31:0] val);
        begin
            if (val > 32'sd32767)       sat_16b = 16'sd32767;
            else if (val < -32'sd32768) sat_16b = -16'sd32768;
            else                        sat_16b = val[15:0];
        end
    endfunction

    function [15:0] abs_16b(input signed [15:0] val);
        begin
            if (val == -16'sd32768) abs_16b = 16'sd32767;
            else                    abs_16b = (val[15]) ? -val : val;
        end
    endfunction

    // ==========================================
    // 6. STATE REGISTERS
    // ==========================================
    reg signed [15:0] lp_reg;
    reg signed [15:0] bp_reg;
    reg signed [15:0] hp_reg;
    reg signed [31:0] mult_res;

    // ==========================================
    // 7. MAIN FSM (uses the active parameter set, never the shadows)
    // ==========================================
    always @(posedge clk) begin
        if (!rstn) begin
            state     <= S_IDLE;
            lp_reg    <= 0;
            bp_reg    <= 0;
            hp_reg    <= 0;
            lp_out    <= 0;
            hp_out    <= 0;
            bp_out    <= 0;
            valid_out <= 0;
            mult_res  <= 0;
        end else begin
            valid_out <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (en) begin
                        // q * bp
                        mult_res <= (bp_reg * active_res);
                        state    <= S_HP_CALC;
                    end
                end

                S_HP_CALC: begin
                    // hp = x - lp - q*bp
                    hp_reg <= sat_16b(audio_in - lp_reg
                                      - ((mult_res + 32'sd16384) >>> 15));
                    state  <= S_F1_MULT;
                end

                S_F1_MULT: begin
                    mult_res <= (hp_reg * active_cutoff);
                    state    <= S_BP_CALC;
                end

                S_BP_CALC: begin
                    // bp = bp + f*hp
                    bp_reg <= sat_16b(bp_reg + ((mult_res + 32'sd16384) >>> 15));
                    state  <= S_F2_MULT;
                end

                S_F2_MULT: begin
                    mult_res <= (bp_reg * active_cutoff);
                    state    <= S_LP_CALC;
                end

                S_LP_CALC: begin
                    // lp = lp + f*bp_new
                    begin : GLOBAL_LCO_CHECK
                        reg signed [15:0] lp_new;
                        lp_new = sat_16b(lp_reg + ((mult_res + 32'sd16384) >>> 15));

                        // Clear a residual limit cycle while the input is silent.
                        if ((audio_in == 0) &&
                            (abs_16b(lp_new) < active_lco) &&
                            (abs_16b(bp_reg) < active_lco) &&
                            (abs_16b(hp_reg) < active_lco))
                        begin
                            lp_reg <= 16'd0;
                            bp_reg <= 16'd0;
                            hp_reg <= 16'd0;
                            lp_out <= 16'd0;
                            hp_out <= 16'd0;
                            bp_out <= 16'd0;
                        end else begin
                            lp_reg <= lp_new;
                            lp_out <= lp_new;
                            hp_out <= hp_reg;
                            bp_out <= bp_reg;
                        end
                    end

                    valid_out <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
