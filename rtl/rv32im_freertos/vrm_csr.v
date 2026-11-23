`timescale 1ns / 1ps

// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// MODULE      : vrm_csr
// DESCRIPTION : Machine-mode CSR block for the RV32IM core: trap entry, MRET,
//               CSR instructions, interrupt masking, and the cycle and
//               instret counters.
//
// Features:
//   - mstatus (0x300)  MIE, MPIE, MPP (WARL)
//   - misa    (0x301)  hardwired RV32IM (0x4000_1100)
//   - mie     (0x304)  MSIE, MTIE, MEIE (WARL)
//   - mtvec   (0x305)  base + mode (WARL, mode 00 or 01)
//   - mscratch(0x340)  read/write
//   - mepc    (0x341)  WARL, 4-byte aligned
//   - mcause  (0x342)  interrupt bit + cause code
//   - mtval   (0x343)  read/write
//   - mip     (0x344)  read-only, driven by the interrupt lines
//   - mcycle  (0xB00), minstret (0xB02): lower 32 bits, read-only
//   - mvendorid/marchid/mimpid/mhartid (0xF11-0xF14): hardwired 0
//
// Interrupt Behavior:
//   - Pending = mstatus.MIE && (mie & mip) for MEIP (11), MTIP (7), MSIP (3).
//   - Priority MEIP > MTIP > MSIP, as in the RISC-V privileged spec.
//   - Update priority: trap_commit > mret_commit > CSR instruction write.
//
// Notes:
//   - Reduced scope: machine mode only. MRET sets MPP to 00 even though no
//     lower privilege mode exists. mcycleh/minstreth are not implemented and
//     the counters cannot be written by software. Unknown CSR addresses
//     raise ex_csr_illegal.
//   - The block has no knowledge of the pipeline; it acts on commit pulses
//     from the core. Reads are combinational, writes synchronous.
//   - Design references: the trap entry/MRET structure follows lowRISC Ibex,
//     the CSR read/write semantics follow Ibex and SERV, and the interrupt
//     pending logic follows PicoRV32 and Ibex. No source code from these
//     projects is included.
// ============================================================================

module vrm_csr (
    input  wire        clk,
    input  wire        rstn,

    // =========================================================================
    // Path 1: CSR instruction (from the EX stage)
    // =========================================================================
    input  wire        ex_csr_en,       // 1 = the EX instruction is a CSR op
    input  wire [11:0] ex_csr_addr,     // instr[31:20]
    input  wire [1:0]  ex_csr_op,       // 00=RW, 01=RS, 10=RC
    input  wire [31:0] ex_csr_src,      // rs1 value or {27'b0, uimm[4:0]}
    output reg  [31:0] ex_csr_rdata,    // old CSR value (for rd)
    output reg         ex_csr_illegal,  // 1 = unknown CSR address

    // =========================================================================
    // Path 2: trap / MRET commit (from the core)
    // =========================================================================
    input  wire        trap_commit,     // 1-cycle pulse when the core takes a trap
    input  wire [31:0] trap_pc,         // PC saved into mepc
    input  wire [3:0]  trap_cause,      // cause code (without the interrupt bit)
    input  wire        trap_is_int,     // 1 = interrupt, 0 = exception
    input  wire [31:0] trap_tval,       // mtval value for the trap (0 if none)

    input  wire        mret_commit,     // 1-cycle pulse when the core commits MRET

    input  wire        instr_retire,    // 1-cycle pulse per instruction retired in WB

    // =========================================================================
    // Interrupt lines (from timer and peripherals)
    // =========================================================================
    input  wire        irq_ext,         // MEIP (cause 11)
    input  wire        irq_timer,       // MTIP (cause 7)
    input  wire        irq_sw,          // MSIP (cause 3)

    // =========================================================================
    // Outputs to the core
    // =========================================================================
    output wire [31:0] csr_mtvec,       // trap target PC
    output wire [31:0] csr_mepc,        // MRET target PC
    output wire        csr_mie_global,  // mstatus.MIE
    output wire [31:0] csr_mie,         // mie register
    output wire [31:0] csr_mip,         // mip register (from the irq lines)
    output wire        csr_int_pending, // 1 = an enabled interrupt is pending
    output wire [3:0]  csr_int_cause,   // cause code of that interrupt

    // Debug
    output wire [63:0] csr_mcycle,      // cycle counter
    output wire [63:0] csr_minstret     // instruction retire counter
);

    // =========================================================================
    // 1. CSR ADDRESS MAP
    // =========================================================================
    localparam [11:0] CSR_MSTATUS   = 12'h300;
    localparam [11:0] CSR_MISA      = 12'h301;
    localparam [11:0] CSR_MIE       = 12'h304;
    localparam [11:0] CSR_MTVEC     = 12'h305;
    localparam [11:0] CSR_MSCRATCH  = 12'h340;
    localparam [11:0] CSR_MEPC      = 12'h341;
    localparam [11:0] CSR_MCAUSE    = 12'h342;
    localparam [11:0] CSR_MTVAL     = 12'h343;
    localparam [11:0] CSR_MIP       = 12'h344;
    localparam [11:0] CSR_MCYCLE    = 12'hB00;
    localparam [11:0] CSR_MINSTRET  = 12'hB02;
    localparam [11:0] CSR_MVENDORID = 12'hF11;
    localparam [11:0] CSR_MARCHID   = 12'hF12;
    localparam [11:0] CSR_MIMPID    = 12'hF13;
    localparam [11:0] CSR_MHARTID   = 12'hF14;

    // =========================================================================
    // 2. CSR STORAGE
    // =========================================================================
    reg [31:0] mstatus_r;
    reg [31:0] mie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;

    // Performance counters
    reg [63:0] mcycle_r;
    reg [63:0] minstret_r;

    // mstatus field aliases
    wire        mstatus_mie  = mstatus_r[3];
    wire        mstatus_mpie = mstatus_r[7];
    wire [1:0]  mstatus_mpp  = mstatus_r[12:11];

    // mip is built from the interrupt lines: MSIP[3], MTIP[7], MEIP[11]
    wire [31:0] mip_value = {20'b0, irq_ext, 3'b0, irq_timer, 3'b0, irq_sw, 3'b0};

    // =========================================================================
    // 3. PERFORMANCE COUNTER UPDATE
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            mcycle_r   <= 64'b0;
            minstret_r <= 64'b0;
        end else begin
            mcycle_r <= mcycle_r + 1'b1;

            // Trap entry and MRET are also counted as retired instructions.
            if (instr_retire || trap_commit || mret_commit) begin
                minstret_r <= minstret_r + 1'b1;
            end
        end
    end

    // =========================================================================
    // 4. CSR READ MUX (combinational)
    // =========================================================================
    always @(*) begin
        ex_csr_illegal = 1'b0;
        case (ex_csr_addr)
            CSR_MSTATUS:   ex_csr_rdata = mstatus_r;
            CSR_MISA:      ex_csr_rdata = 32'h40001100; // MXL=01 (RV32), I and M extensions
            CSR_MIE:       ex_csr_rdata = mie_r;
            CSR_MTVEC:     ex_csr_rdata = mtvec_r;
            CSR_MSCRATCH:  ex_csr_rdata = mscratch_r;
            CSR_MEPC:      ex_csr_rdata = mepc_r;
            CSR_MCAUSE:    ex_csr_rdata = mcause_r;
            CSR_MTVAL:     ex_csr_rdata = mtval_r;
            CSR_MIP:       ex_csr_rdata = mip_value;
            CSR_MCYCLE:    ex_csr_rdata = mcycle_r[31:0];
            CSR_MINSTRET:  ex_csr_rdata = minstret_r[31:0];
            CSR_MVENDORID: ex_csr_rdata = 32'h00000000;
            CSR_MARCHID:   ex_csr_rdata = 32'h00000000;
            CSR_MIMPID:    ex_csr_rdata = 32'h00000000;
            CSR_MHARTID:   ex_csr_rdata = 32'h00000000;
            default: begin
                ex_csr_rdata   = 32'h00000000;
                ex_csr_illegal = 1'b1;
            end
        endcase
    end

    // =========================================================================
    // 5. CSR WRITE VALUE COMPUTATION
    // =========================================================================
    // CSRRW / CSRRWI (00): write src
    // CSRRS / CSRRSI (01): set bits   -> old | src
    // CSRRC / CSRRCI (10): clear bits -> old & ~src
    reg [31:0] csr_new_val;
    always @(*) begin
        case (ex_csr_op)
            2'b00:    csr_new_val = ex_csr_src;
            2'b01:    csr_new_val = ex_csr_rdata | ex_csr_src;
            2'b10:    csr_new_val = ex_csr_rdata & ~ex_csr_src;
            default:  csr_new_val = ex_csr_rdata;
        endcase
    end

    // CSRRW always writes. CSRRS/CSRRC write only when src != 0, so a pure
    // read has no write side effect, as the RISC-V spec requires.
    wire csr_do_write =
        ex_csr_en && !ex_csr_illegal &&
        ((ex_csr_op == 2'b00) || (ex_csr_src != 32'b0));

    // =========================================================================
    // 6. WARL WRITE MASKS
    // =========================================================================
    // Bits writable by software; the rest are read-only or hardwired.
    localparam [31:0] MSTATUS_WMASK = 32'h00001888; // MIE[3], MPIE[7], MPP[12:11]
    localparam [31:0] MIE_WMASK     = 32'h00000888; // MSIE[3], MTIE[7], MEIE[11]

    // =========================================================================
    // 7. SEQUENTIAL UPDATE
    //    Priority: trap_commit > mret_commit > csr_do_write
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            // MPP = 11 (M-mode), MIE = 0, MPIE = 0, other fields 0
            mstatus_r  <= 32'h00001800;
            mie_r      <= 32'h00000000;
            mtvec_r    <= 32'h00000000;
            mscratch_r <= 32'h00000000;
            mepc_r     <= 32'h00000000;
            mcause_r   <= 32'h00000000;
            mtval_r    <= 32'h00000000;

        end else if (trap_commit) begin
            // ----- Trap entry (order as in the RISC-V privileged spec) -----
            // mepc <= PC (4-byte aligned)
            mepc_r           <= {trap_pc[31:2], 2'b00};
            // mcause <= {interrupt, cause}
            mcause_r         <= {trap_is_int, 27'b0, trap_cause};
            mtval_r          <= trap_tval;
            // mstatus: MPIE <= MIE, MIE <= 0, MPP <= 11 (M-mode)
            mstatus_r[7]     <= mstatus_mie;
            mstatus_r[3]     <= 1'b0;
            mstatus_r[12:11] <= 2'b11;
            // Other mstatus fields are kept
            mstatus_r[31:13] <= mstatus_r[31:13];
            mstatus_r[10:8]  <= mstatus_r[10:8];
            mstatus_r[6:4]   <= mstatus_r[6:4];
            mstatus_r[2:0]   <= mstatus_r[2:0];

        end else if (mret_commit) begin
            // ----- MRET (order as in the RISC-V privileged spec) -----
            // MIE <= MPIE
            mstatus_r[3]     <= mstatus_mpie;
            // MPIE <= 1
            mstatus_r[7]     <= 1'b1;
            // MPP <= 00 (least privileged mode; only M-mode exists here)
            mstatus_r[12:11] <= 2'b00;
            // Other mstatus fields are kept
            mstatus_r[31:13] <= mstatus_r[31:13];
            mstatus_r[10:8]  <= mstatus_r[10:8];
            mstatus_r[6:4]   <= mstatus_r[6:4];
            mstatus_r[2:0]   <= mstatus_r[2:0];

        end else if (csr_do_write) begin
            // ----- CSR instruction -----
            case (ex_csr_addr)
                CSR_MSTATUS: begin
                    mstatus_r <= (mstatus_r & ~MSTATUS_WMASK)
                               | (csr_new_val & MSTATUS_WMASK);
                end
                CSR_MIE: begin
                    mie_r <= (mie_r & ~MIE_WMASK)
                           | (csr_new_val & MIE_WMASK);
                end
                CSR_MTVEC: begin
                    // WARL: mode is 00 or 01. The base is forced to 4-byte
                    // alignment, which is sufficient without compressed
                    // instructions.
                    mtvec_r <= {csr_new_val[31:2],
                                (csr_new_val[1:0] == 2'b01) ? 2'b01 : 2'b00};
                end
                CSR_MSCRATCH: mscratch_r <= csr_new_val;
                CSR_MEPC:     mepc_r     <= {csr_new_val[31:2], 2'b00};
                CSR_MCAUSE:   mcause_r   <= csr_new_val;
                CSR_MTVAL:    mtval_r    <= csr_new_val;
                // mip, the counters, and the ID registers are read-only.
                default: ; // writes to read-only addresses are ignored
            endcase
        end
    end

    // =========================================================================
    // 8. INTERRUPT PENDING DETECTION (combinational)
    // =========================================================================
    // An interrupt is taken when the global MIE is set and (mie & mip) != 0.
    wire [31:0] int_effective = mip_value & mie_r;

    wire int_ext_ok   = int_effective[11]; // MEIP
    wire int_timer_ok = int_effective[7];  // MTIP
    wire int_sw_ok    = int_effective[3];  // MSIP

    assign csr_int_pending = mstatus_mie && (int_ext_ok | int_timer_ok | int_sw_ok);

    // Priority MEIP > MTIP > MSIP (RISC-V privileged spec)
    assign csr_int_cause = int_ext_ok   ? 4'd11 :
                           int_timer_ok ? 4'd7  :
                           int_sw_ok    ? 4'd3  : 4'd0;

    // =========================================================================
    // 9. OUTPUTS
    // =========================================================================
    assign csr_mtvec      = mtvec_r;
    assign csr_mepc       = mepc_r;
    assign csr_mie_global = mstatus_mie;
    assign csr_mie        = mie_r;
    assign csr_mip        = mip_value;
    assign csr_mcycle     = mcycle_r;
    assign csr_minstret   = minstret_r;

endmodule
