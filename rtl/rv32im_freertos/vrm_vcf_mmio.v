`timescale 1ns / 1ps
`include "vrm_soc_map_rv32i.vh"
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_vcf_mmio
// DESCRIPTION : Stereo voltage-controlled-filter (VCF) block: MMIO register
//               slave on the CPU bus, read-only host port, and an
//               AXI4-Stream audio datapath through two vrm_vcf_core channels.
//
// Features:
//   - Stereo 32-bit samples {R[31:16], L[15:0]}.
//   - Shadow registers with an atomic commit at a zero crossing, armed
//     independently per channel.
//   - Zero-latency bypass when enable = 0.
//
// Registers (byte offset from VCF_BASE_ADDR = 0x8000_2000):
//   0x00 CTRL    W : [0]   enable
//                    [2]   commit arm (write 5 = enable + LP + commit)
//                    [4:3] filter type (0=LP, 1=HP, 2=BP)
//                R : reg_ctrl | {commit_status, 31'b0}
//   0x04 CUTOFF    : Q1.15 shadow
//   0x08 RES       : Q1.15 shadow
//   0x0C LCO       : unsigned shadow
//   0x10-0x3C      : read 0, write ignored
//   Reset values: CTRL 0 (bypass), CUTOFF 0x4000, RES 0x0800, LCO 15, LP.
//
// Commit protocol:
//   - Every write to CTRL/CUTOFF/RES/LCO cancels a pending commit.
//   - A CTRL write with bit 2 = 1 arms the commit (L and R).
//   - The last write of an update sequence must therefore be CTRL with
//     bit 2 = 1. All shadow values written before it are applied together,
//     in the same sample, per channel, so a preset is never applied half way.
//   - An armed channel commits after the first sample that crosses zero
//     after the arm (sign change against the previous filtered sample, or a
//     sample equal to 0). Crossings seen before the arm do not count.
//   - Timeout: without a fresh crossing within ZCD_TIMEOUT_SAMPLES filtered
//     samples, the commit is forced at the next sample boundary.
//   - Commits only happen while enable = 1 (samples flow through the cores).
//
// Notes:
//   - LIMITATION: vrm_vcf_core also requires its own crossing latch, which
//     is set by any crossing since its last commit. A timeout cannot
//     complete if the input has not crossed zero at all since the previous
//     commit (for example a constant DC input); the commit then stays armed
//     (CTRL[31] = 1) until the next crossing.
//   - All register state changes are gated by mmio_cs && mmio_we.
//   - Reads are combinational and side-effect free; mmio_rdata is 0 when
//     mmio_cs is low. The host port reads the same registers independently.
// ============================================================================

module vrm_vcf_mmio #(
    // Filtered samples to wait for a fresh zero crossing before a commit is
    // forced. 2400 = 50 ms at 48 kHz. 0 = no timeout. Max 65535.
    parameter integer ZCD_TIMEOUT_SAMPLES = 2400
) (
    input  wire        clk,
    input  wire        rstn,

    // --- MMIO slave interface ---
    input  wire        mmio_cs,
    input  wire        mmio_we,
    input  wire [3:0]  mmio_addr,
    input  wire [31:0] mmio_wdata,
    output wire [31:0] mmio_rdata,

    // Read-only host port. Reading does not alter shadow or commit state.
    input  wire [3:0]  host_read_addr,
    output wire [31:0] host_read_data,

    // --- AXI4-Stream audio input ---
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // --- AXI4-Stream audio output ---
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // =========================================================================
    // 1. MMIO REGISTERS AND SHADOWS
    // =========================================================================
    reg [31:0] reg_ctrl;
    reg [15:0] shadow_cutoff;
    reg [15:0] shadow_res;
    reg [15:0] shadow_lco;
    reg [1:0]  shadow_ftype;
    reg        commit_armed_set;   // 1-cycle pulse to the armed latch
    reg        commit_armed_clr;   // 1-cycle pulse: cancel pending commit

    // Armed per channel (independent)
    reg        commit_armed_l;
    reg        commit_armed_r;
    wire       commit_status = commit_armed_l | commit_armed_r;

    wire       enable_vcf = reg_ctrl[`VCF_CTRL_BIT_ENABLE];
    wire       mmio_wr    = mmio_cs && mmio_we;

    // --- MMIO write (single writer for every register below) ---
    always @(posedge clk) begin
        if (!rstn) begin
            reg_ctrl         <= 32'h0000_0000;
            shadow_cutoff    <= 16'h4000;   // cutoff default 0.5
            shadow_res       <= 16'h0800;   // Q ~ 16
            shadow_lco       <= 16'd15;
            shadow_ftype     <= 2'd0;       // LP
            commit_armed_set <= 1'b0;
            commit_armed_clr <= 1'b0;
        end else begin
            commit_armed_set <= 1'b0;
            commit_armed_clr <= 1'b0;

            if (mmio_wr) begin
                case (mmio_addr)
                    `VCF_REG_CTRL: begin
                        reg_ctrl     <= mmio_wdata;
                        shadow_ftype <= mmio_wdata[`VCF_CTRL_FTYPE_LSB +: 2];
                        // bit 2 = 1: (re)arm, bit 2 = 0: cancel
                        if (mmio_wdata[`VCF_CTRL_BIT_COMMIT])
                            commit_armed_set <= 1'b1;
                        else
                            commit_armed_clr <= 1'b1;
                    end
                    // Shadow writes cancel a pending commit, so a commit can
                    // never apply a half-written parameter set.
                    `VCF_REG_CUTOFF: begin
                        shadow_cutoff    <= mmio_wdata[15:0];
                        commit_armed_clr <= 1'b1;
                    end
                    `VCF_REG_RES: begin
                        shadow_res       <= mmio_wdata[15:0];
                        commit_armed_clr <= 1'b1;
                    end
                    `VCF_REG_LCO: begin
                        shadow_lco       <= mmio_wdata[15:0];
                        commit_armed_clr <= 1'b1;
                    end
                    default: ;                      // reserved: ignored
                endcase
            end
        end
    end

    // --- MMIO reads (combinational, no side effects) ---
    function [31:0] read_register;
        input [3:0]  word_addr;
        input [31:0] ctrl;
        input [15:0] cutoff, resonance, lco;
        begin
            case (word_addr)
                `VCF_REG_CTRL:   read_register = ctrl;
                `VCF_REG_CUTOFF: read_register = {16'b0, cutoff};
                `VCF_REG_RES:    read_register = {16'b0, resonance};
                `VCF_REG_LCO:    read_register = {16'b0, lco};
                default:         read_register = 32'h0000_0000;
            endcase
        end
    endfunction

    wire [31:0] ctrl_read = {commit_status, 31'b0} | reg_ctrl;
    assign mmio_rdata = mmio_cs ?
        read_register(mmio_addr, ctrl_read, shadow_cutoff, shadow_res, shadow_lco) : 32'h0;
    assign host_read_data =
        read_register(host_read_addr, ctrl_read, shadow_cutoff, shadow_res, shadow_lco);

    // =========================================================================
    // 2. VCF CORES (LEFT AND RIGHT)
    // =========================================================================
    reg         vcf_en;
    reg  [15:0] latched_l;
    reg  [15:0] latched_r;

    wire [15:0] lp_l, hp_l, bp_l;
    wire [15:0] lp_r, hp_r, bp_r;
    wire        vcf_valid_l, vcf_valid_r;
    wire        commit_ack_l, commit_ack_r;
    wire [1:0]  ftype_active_l, ftype_active_r;
    wire        commit_req_l, commit_req_r;    // gated, see section 4

    // --- LEFT (armed_l) ---
    vrm_vcf_core core_l (
        .clk(clk), .rstn(rstn), .en(vcf_en),
        .audio_in(latched_l),
        .cutoff_shadow(shadow_cutoff),
        .res_shadow(shadow_res),
        .lco_shadow(shadow_lco),
        .ftype_shadow(shadow_ftype),
        .commit_req(commit_req_l),
        .lp_out(lp_l), .hp_out(hp_l), .bp_out(bp_l),
        .ftype_active(ftype_active_l),
        .commit_ack(commit_ack_l),
        .valid_out(vcf_valid_l)
    );

    // --- RIGHT (armed_r) ---
    vrm_vcf_core core_r (
        .clk(clk), .rstn(rstn), .en(vcf_en),
        .audio_in(latched_r),
        .cutoff_shadow(shadow_cutoff),
        .res_shadow(shadow_res),
        .lco_shadow(shadow_lco),
        .ftype_shadow(shadow_ftype),
        .commit_req(commit_req_r),
        .lp_out(lp_r), .hp_out(hp_r), .bp_out(bp_r),
        .ftype_active(ftype_active_r),
        .commit_ack(commit_ack_r),
        .valid_out(vcf_valid_r)
    );

    // =========================================================================
    // 3. COMMIT ARMED LATCH (per channel, independent)
    // =========================================================================
    //   Set both on a commit-arming CTRL write.
    //   Clear both on any other register write (cancel).
    //   Clear each when its own channel has committed.
    //   L may commit before R; R stays armed until its own crossing.
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            commit_armed_l <= 1'b0;
            commit_armed_r <= 1'b0;
        end else begin
            if (commit_armed_set) begin
                commit_armed_l <= 1'b1;
                commit_armed_r <= 1'b1;
            end else if (commit_armed_clr) begin
                commit_armed_l <= 1'b0;
                commit_armed_r <= 1'b0;
            end else begin
                if (commit_ack_l) commit_armed_l <= 1'b0;
                if (commit_ack_r) commit_armed_r <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. FRESH-CROSSING COMMIT GATE
    // =========================================================================
    //   A crossing is evaluated on every sample entering the cores (vcf_en),
    //   with the same rule as vrm_vcf_core: sign change against the previous
    //   sample, or sample == 0. The previous sign is only trusted after one
    //   sample has been filtered since enable (prev_valid), so the first
    //   sample after a bypass period is not compared with a stale sign.
    //
    //   zcd_seen_x is cleared on arm/cancel and set by a crossing while the
    //   channel is armed, so only crossings after the arm count. The core's
    //   own crossing latch is set by the same sample, so the core commits at
    //   the first idle cycle after that sample (before the next vcf_en).
    //   Without this gate, a crossing latched before the arm could let the
    //   core commit away from a zero crossing.
    //
    //   commit_req_x only rises in the cycle after vcf_en (core busy), so a
    //   commit never coincides with the start of a sample.
    // =========================================================================
    localparam [15:0] ZCD_TMO = ZCD_TIMEOUT_SAMPLES;

    reg        prev_sign_l, prev_sign_r;
    reg        prev_valid;
    reg        zcd_seen_l, zcd_seen_r;
    reg [15:0] tmo_cnt;                 // samples filtered since the arm

    wire cross_l = (latched_l == 16'd0) ||
                   (prev_valid && (latched_l[15] != prev_sign_l));
    wire cross_r = (latched_r == 16'd0) ||
                   (prev_valid && (latched_r[15] != prev_sign_r));

    wire tmo_hit = (ZCD_TMO != 16'd0) && (tmo_cnt >= ZCD_TMO);

    assign commit_req_l = commit_armed_l && (zcd_seen_l || tmo_hit);
    assign commit_req_r = commit_armed_r && (zcd_seen_r || tmo_hit);

    always @(posedge clk) begin
        if (!rstn) begin
            prev_sign_l <= 1'b0;
            prev_sign_r <= 1'b0;
            prev_valid  <= 1'b0;
            zcd_seen_l  <= 1'b0;
            zcd_seen_r  <= 1'b0;
            tmo_cnt     <= 16'd0;
        end else begin
            // Previous-sample sign, valid only while samples are filtered
            if (!enable_vcf) begin
                prev_valid <= 1'b0;
            end else if (vcf_en) begin
                prev_sign_l <= latched_l[15];
                prev_sign_r <= latched_r[15];
                prev_valid  <= 1'b1;
            end

            if (commit_armed_set || commit_armed_clr) begin
                zcd_seen_l <= 1'b0;
                zcd_seen_r <= 1'b0;
                tmo_cnt    <= 16'd0;
            end else begin
                if (vcf_en) begin
                    if (commit_armed_l && cross_l) zcd_seen_l <= 1'b1;
                    if (commit_armed_r && cross_r) zcd_seen_r <= 1'b1;
                    if (commit_status && (tmo_cnt != 16'hFFFF))
                        tmo_cnt <= tmo_cnt + 16'd1;
                end
                if (commit_ack_l) zcd_seen_l <= 1'b0;
                if (commit_ack_r) zcd_seen_r <= 1'b0;
                if (!commit_status) tmo_cnt <= 16'd0;
            end
        end
    end

    // =========================================================================
    // 5. AUDIO DATAPATH FSM AND MUX
    // =========================================================================
    //   ST_WAIT_IN  : accept one stereo sample, start both cores
    //   ST_WAIT_VCF : wait for the left core result, capture both channels
    //   ST_SEND_OUT : hold m_axis valid until m_axis_tready
    //   One sample is in flight at a time; s_axis_tready is low meanwhile.
    // =========================================================================
    localparam [1:0] ST_WAIT_IN  = 2'd0;
    localparam [1:0] ST_WAIT_VCF = 2'd1;
    localparam [1:0] ST_SEND_OUT = 2'd2;

    reg [1:0]  state;
    reg        latched_tlast;
    reg [31:0] out_data_reg;

    // Output selection uses the committed filter type of each core
    wire [15:0] final_l = (ftype_active_l == 2'd0) ? lp_l :
                          (ftype_active_l == 2'd1) ? hp_l : bp_l;
    wire [15:0] final_r = (ftype_active_r == 2'd0) ? lp_r :
                          (ftype_active_r == 2'd1) ? hp_r : bp_r;

    always @(posedge clk) begin
        if (!rstn || !enable_vcf) begin
            state         <= ST_WAIT_IN;
            vcf_en        <= 1'b0;
            out_data_reg  <= 32'b0;
            latched_tlast <= 1'b0;
            latched_l     <= 16'b0;
            latched_r     <= 16'b0;
        end else begin
            case (state)
                ST_WAIT_IN: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        latched_l     <= s_axis_tdata[15:0];
                        latched_r     <= s_axis_tdata[31:16];
                        latched_tlast <= s_axis_tlast;
                        vcf_en        <= 1'b1;
                        state         <= ST_WAIT_VCF;
                    end
                end
                ST_WAIT_VCF: begin
                    vcf_en <= 1'b0;                 // 1-cycle enable pulse
                    if (vcf_valid_l) begin
                        out_data_reg <= {final_r, final_l};
                        state        <= ST_SEND_OUT;
                    end
                end
                ST_SEND_OUT: begin
                    if (m_axis_tready) begin
                        state <= ST_WAIT_IN;
                    end
                end
                default: state <= ST_WAIT_IN;
            endcase
        end
    end

    // =========================================================================
    // 6. HARDWARE BYPASS MULTIPLEXER
    // =========================================================================
    // tvalid never depends on tready in either mode.
    assign s_axis_tready = enable_vcf ? (state == ST_WAIT_IN)  : m_axis_tready;
    assign m_axis_tvalid = enable_vcf ? (state == ST_SEND_OUT) : s_axis_tvalid;
    assign m_axis_tdata  = enable_vcf ? out_data_reg  : s_axis_tdata;
    assign m_axis_tlast  = enable_vcf ? latched_tlast : s_axis_tlast;

endmodule
