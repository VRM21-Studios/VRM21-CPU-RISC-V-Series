`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// Testbench   : tb_freertos_axi
// Description : FreeRTOS system test of vrm_soc_axi through its AXI4-Lite,
//               AXI4-Stream, and GPIO interrupt ports. Used as the suite
//               inside tb_freertos_autoboot (AUTOBOOT = 1) or stand-alone with
//               AXI image injection (AUTOBOOT = 0).
//               Expected values: the diagnostic block written by the firmware
//               at 0x1000_F000 (marker 0x46525431, tick, TX, RX, semaphore,
//               idle, preemption, fault) and the VCF presets of the firmware
//               (FX2 cutoff 0x1999, CLEAR cutoff 0x2666).
//               Phases and checks:
//                 1. Scheduler to tick 40: TX/RX/semaphore >= 3, idle and
//                    preemption > 0, fault 0.
//                 2. GPIO bit 2 (FX2): CTRL/CUTOFF readback, 16 filtered beats
//                    under backpressure with correct TLAST, 8 concurrent host
//                    reads, commit applied.
//                 3. GPIO bit 0 (CLEAR): bypass, 16 unchanged beats.
//                 4. Warm reset through CPU_CTRL and scheduler to tick 40 again.
//                 5. MTIP-to-trap latency sampled during DIV and REM.
//               +host_overlap instead runs one probe: a host CUTOFF read in
//               the same cycle as a CPU store must return 0x2666 and the
//               store must land (TX counter + 1).
// Parameters  : AUTOBOOT (module parameter). With AUTOBOOT = 0 the run
//               directory needs a seed firmware.mem (WFI loop) and
//               payload.words, and +words=<n> gives the payload length.
//               Watchdog: 10,000,000 clock cycles.
// Result      : ">>> TEST PASSED <<<" on success; any failure ends with
//               $fatal and a message (no PASS line is printed).
// ============================================================================
module tb_freertos_axi #(parameter bit AUTOBOOT = 0);
    reg         aclk;
    reg         aresetn;
    reg  [31:0] awaddr;  reg awvalid; wire awready;
    reg  [31:0] wdata;   reg wvalid;  wire wready;  reg [3:0] wstrb;
    wire [1:0]  bresp;   wire bvalid; reg bready;
    reg  [31:0] araddr;  reg arvalid; wire arready;
    wire [31:0] rdata;   wire [1:0] rresp; wire rvalid; reg rready;

    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready;

    reg  [30:0] ext_irq_in;
    wire        cpu_halt;
    wire [31:0] cpu_pc;
    wire [31:0] debug_reg_x1;

    vrm_soc_axi #(
        .C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(32),
        .C_AXIS_IN_WIDTH(32),    .C_AXIS_OUT_WIDTH(32), .BOOT_FREERTOS(AUTOBOOT)
    ) uut (
        .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast), .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast), .m_axis_tready(m_axis_tready),
        .ext_irq_in(ext_irq_in),
        .cpu_halt(cpu_halt), .cpu_pc(cpu_pc), .debug_reg_x1(debug_reg_x1)
    );

    task axi_write(input [31:0] addr, input [31:0] data);
    begin
        @(negedge aclk);
        awaddr = addr; awvalid = 1'b1;
        wdata  = data; wvalid  = 1'b1; wstrb = 4'hF; bready = 1'b1;
        fork
            begin do @(posedge aclk); while (!awready); @(negedge aclk) awvalid = 1'b0; end
            begin do @(posedge aclk); while (!wready);  @(negedge aclk) wvalid  = 1'b0; end
        join
        do @(posedge aclk); while (!bvalid);
        @(negedge aclk) bready = 1'b0;
    end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data_out);
    begin
        @(negedge aclk);
        araddr = addr; arvalid = 1'b1; rready = 1'b1;
        do @(posedge aclk); while (!arready);
        @(negedge aclk) arvalid = 1'b0;
        do @(posedge aclk); while (!rvalid);
        data_out = rdata;
        @(negedge aclk) rready = 1'b0;
    end
    endtask

    localparam logic [31:0] CPU_CTRL = 32'h0000c000;
    localparam logic [31:0] IMAGE_BASE = 32'h10001000;
    localparam logic [31:0] VCF_CTRL = 32'h80002000;
    localparam logic [31:0] VCF_CUTOFF = VCF_CTRL + 4;
    // FX2 = enable | explicit commit arm | HP selection (1 << 3).
    localparam logic [31:0] FX2_CTRL = (1 << 0) | (1 << 2) | (1 << 3);
    localparam integer DIAG_BASE = 15360;
    `define SOC uut.vrm_soc_inst
    `define CORE uut.vrm_soc_inst.cpu_sys_inst.core

    reg [31:0] image [0:5119];
    integer image_words;
    integer image_file;
    integer cycles = 0;
    integer div_irqs = 0;
    integer rem_irqs = 0;
    integer div_max = 0;
    integer rem_max = 0;
    integer irq_cycle = 0;
    integer irq_md_op = 0;
    reg previous_irq = 1'b0;
    wire timer_irq = `SOC.cpu_sys_inst.timer_irq;
    wire [31:0] ticks = `SOC.ram[DIAG_BASE + 1];
    wire [31:0] fault_code = `SOC.ram[DIAG_BASE + 7];

    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    always @(posedge aclk) begin
        cycles = cycles + 1;
        previous_irq <= timer_irq;
        if (timer_irq && !previous_irq) begin
            irq_cycle = cycles;
            irq_md_op = `CORE.mdu_hold ? int'(`CORE.id_ex_funct3) : 0;
        end
        if (`CORE.core_trap_commit && `CORE.core_trap_is_int &&
            `CORE.core_trap_cause == 4'd7) begin
            if (irq_md_op == 4) begin
                div_irqs = div_irqs + 1;
                if (cycles - irq_cycle > div_max)
                    div_max = cycles - irq_cycle;
            end
            if (irq_md_op == 6) begin
                rem_irqs = rem_irqs + 1;
                if (cycles - irq_cycle > rem_max)
                    rem_max = cycles - irq_cycle;
            end
            irq_md_op = 0;
        end
    end

    task check_read(input logic [31:0] address, expected, mask);
        logic [31:0] value;
        begin
            axi_read(address, value);
            if ((value & mask) !== expected)
                $fatal(1, "AXI read %08x got %08x expected %08x mask %08x",
                       address, value, expected, mask);
        end
    endtask

    task check_scheduler(input integer minimum_ticks, minimum_messages);
        begin
            wait (ticks >= minimum_ticks || fault_code != 0);
            @(negedge aclk);
            $display("SCHED ticks=%0d tx=%0d rx=%0d sem=%0d idle=%0d preempt=%0d fault=%08x",
                     ticks, `SOC.ram[DIAG_BASE+2], `SOC.ram[DIAG_BASE+3],
                     `SOC.ram[DIAG_BASE+4], `SOC.ram[DIAG_BASE+5],
                     `SOC.ram[DIAG_BASE+6], fault_code);
            if (fault_code !== 0 || `SOC.ram[DIAG_BASE] !== 32'h46525431 ||
                `SOC.ram[DIAG_BASE+2] < minimum_messages ||
                `SOC.ram[DIAG_BASE+3] < minimum_messages ||
                `SOC.ram[DIAG_BASE+4] < minimum_messages ||
                `SOC.ram[DIAG_BASE+5] == 0 || `SOC.ram[DIAG_BASE+6] == 0)
                $fatal(1, "Scheduler checks failed");
        end
    endtask

    task pulse_gpio(input integer bit_number);
        begin
            @(negedge aclk);
            ext_irq_in = 31'd1 << bit_number;
            repeat (12) @(negedge aclk);
            ext_irq_in = 0;
        end
    endtask

    function automatic logic [31:0] audio_sample(input integer i);
        if ((i % 4) < 2)
            audio_sample = 32'hf0002000;
        else
            audio_sample = 32'h1000e000;
    endfunction

    task drive_audio;
        begin
            for (integer i = 0; i < 16; ++i) begin
                @(negedge aclk);
                s_axis_tvalid = 1'b1;
                s_axis_tdata = audio_sample(i);
                s_axis_tlast = (i == 15);
                do @(posedge aclk); while (!s_axis_tready);
            end
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task check_audio(input bit expect_bypass);
        integer output_count, changed, stalled;
        bit held;
        logic [32:0] previous;
        begin
            output_count = 0;
            changed = 0;
            stalled = 0;
            held = 0;
            while (output_count < 16) begin
                @(negedge aclk);
                m_axis_tready = (cycles % 7 >= 3);
                @(posedge aclk);
                if (held && (!m_axis_tvalid || {m_axis_tlast, m_axis_tdata} !== previous))
                    $fatal(1, "AXI-Stream payload changed while stalled");
                if (m_axis_tvalid && m_axis_tready) begin
                    if (m_axis_tlast !== (output_count == 15))
                        $fatal(1, "AXI-Stream TLAST at sample %0d", output_count);
                    if (m_axis_tdata !== audio_sample(output_count))
                        changed = changed + 1;
                    output_count = output_count + 1;
                end
                held = m_axis_tvalid && !m_axis_tready;
                previous = {m_axis_tlast, m_axis_tdata};
                if (held)
                    stalled = stalled + 1;
            end
            if ((expect_bypass && changed != 0) || (!expect_bypass && changed == 0) ||
                stalled == 0)
                $fatal(1, "Unexpected audio summary bypass=%0b changed=%0d stalls=%0d",
                       expect_bypass, changed, stalled);
            $display("AUDIO bypass=%0b beats=%0d changed=%0d stalls=%0d",
                     expect_bypass, output_count, changed, stalled);
            @(negedge aclk);
            m_axis_tready = 1'b1;
        end
    endtask

    task probe_host_overlap;
        logic [31:0] old_count;
        logic [31:0] host_value;
        bit shared_cycle;
        begin
            wait (ticks >= 10);
            wait (`CORE.id_ex_mem_we && `CORE.ex_result == 32'h1000f008);
            old_count = `SOC.ram[DIAG_BASE+2];
            shared_cycle = 0;
            fork
                begin
                    axi_read(VCF_CUTOFF, host_value);
                end
                begin
                    repeat (4) begin
                        @(posedge aclk);
                        if (`SOC.host_re && `SOC.cpu_mem_we &&
                            `SOC.cpu_mem_addr == 32'h1000f008)
                            shared_cycle = 1;
                    end
                end
            join
            $display("HOST_OVERLAP coincident=%0b host=%08x tx_before=%0d tx_after=%0d",
                     shared_cycle, host_value, old_count, `SOC.ram[DIAG_BASE+2]);
            if (!shared_cycle || host_value !== 32'h2666)
                $fatal(1, "Host overlap stimulus did not reach intended arbitration");
            if (`SOC.ram[DIAG_BASE+2] !== old_count + 1)
                $fatal(1, "AXI host VCF read suppressed an RV32IM RAM store");
        end
    endtask

    initial begin
        if (!AUTOBOOT) begin
            if (!$value$plusargs("words=%d", image_words) || image_words < 2 || image_words > 5120)
                $fatal(1, "Invalid AXI transfer length");
            image_file = $fopen("payload.words", "r");
            if (image_file == 0)
                $fatal(1, "payload.words missing");
            $fclose(image_file);
            $readmemh("payload.words", image, 0, image_words - 1);
            if (image[0] !== 32'h30401073)
                $fatal(1, "AXI payload startup marker mismatch %08x", image[0]);

        end

        aresetn = 0;
        awaddr = 0; awvalid = 0; wdata = 0; wvalid = 0; wstrb = 0; bready = 0;
        araddr = 0; arvalid = 0; rready = 0;
        s_axis_tdata = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
        m_axis_tready = 1;
        ext_irq_in = 0;
        repeat (5) @(negedge aclk);
        aresetn = 1;
        if (AUTOBOOT) begin
            wait (uut.cpu_release);
        end else begin
            wait (uut.cpu_release && cpu_halt);
            if (`SOC.ram[0] !== 32'h10500073)
                $fatal(1, "Bootloader seed did not execute");

            axi_write(CPU_CTRL, 0);
            check_read(CPU_CTRL, 0, 32'hffffffff);
            for (integer i = 0; i < image_words; ++i)
                axi_write(IMAGE_BASE + 4*i, image[i]);
            axi_write(0, 32'h100012b7); // lui t0,0x10001
            axi_write(4, 32'h00028067); // jr t0
            check_read(0, 32'h100012b7, 32'hffffffff);
            check_read(IMAGE_BASE, image[0], 32'hffffffff);
            check_read(IMAGE_BASE + 4*(image_words-1), image[image_words-1], 32'hffffffff);
            $display("AXI loaded %0d words into production RAM; boot seed and endpoint readback OK", image_words);
            axi_write(CPU_CTRL, 1);

        end

        if ($test$plusargs("host_overlap")) begin
            probe_host_overlap();
            $display(">>> TEST PASSED <<<");
            $finish;
        end

        check_scheduler(40, 3);
        wait (cpu_halt);
        pulse_gpio(2);
        wait (cpu_halt && (`SOC.vcf_inst.reg_ctrl & 32'h1f) == FX2_CTRL);
        check_read(VCF_CTRL, 32'h80000000 | FX2_CTRL, 32'h8000001f);
        fork
            begin drive_audio(); end
            begin check_audio(0); end
            begin
                repeat (8) check_read(VCF_CUTOFF, 32'h1999, 32'hffffffff);
                $display("AXI readback concurrent with filtered audio: 8 reads");
            end
        join
        if (`SOC.vcf_inst.commit_status !== 1'b0 ||
            `SOC.vcf_inst.core_l.active_cutoff !== 16'h1999)
            $fatal(1, "FX2 did not commit the expected cutoff");
        pulse_gpio(0);
        wait (cpu_halt && `SOC.vcf_inst.reg_ctrl[0] == 0);
        check_read(VCF_CUTOFF, 32'h2666, 32'hffffffff);
        fork
            begin drive_audio(); end
            begin check_audio(1); end
        join
        $display("VCF FX2 and CLEAR passed through GPIO");

        axi_write(CPU_CTRL, 0);
        check_read(CPU_CTRL, 0, 32'hffffffff);
        axi_write(CPU_CTRL, 1);
        wait (`SOC.ram[DIAG_BASE] == 32'h46525431 && ticks == 0);
        check_scheduler(40, 3);
        $display("CPU_CTRL warm reset: data, BSS, and scheduler restarted");
        $display("MDU IRQ timing: DIV=%0d max=%0d cycles, REM=%0d max=%0d cycles",
                 div_irqs, div_max, rem_irqs, rem_max);
        if (div_irqs == 0 || rem_irqs == 0)
            $fatal(1, "No measured IRQ sample during DIV or REM");
        $display(">>> TEST PASSED <<<");
        $finish;
    end

    initial begin
        repeat (10000000) @(posedge aclk);
        $fatal(1, "FreeRTOS watchdog PC=%08x ticks=%0d fault=%08x cpu_halt=%0b",
               cpu_pc, ticks, fault_code, cpu_halt);
    end
    `undef SOC
    `undef CORE
endmodule
