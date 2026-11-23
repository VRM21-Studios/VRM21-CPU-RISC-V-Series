`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// Testbench   : tb_freertos_autoboot
// Description : Cold boot of the production SoC (vrm_soc_axi, BOOT_FREERTOS
//               = 1) followed by the full FreeRTOS suite of tb_freertos_axi.
//               Expected values come from include/rv32im_freertos/firmware.mem,
//               read here as a byte image.
//               Boot checks: no host AXI write during boot; every one of the
//               4096 boot writes lands at 0x1000_1000 + 4*i with the expected
//               word; the reset trampoline (0x100012b7, 0x00028067) is written
//               at 0x0/0x4; the CPU stays in reset until the last write; the
//               RAM content matches the image at release.
//               After release, tb_freertos_axi runs the scheduler, GPIO/VCF,
//               audio, warm-reset, and MDU interrupt-latency phases.
// Parameters  : BOOT_BYTES / IMAGE_BASE below; firmware.mem must be in the
//               simulator run directory. Plusarg +host_overlap runs only the
//               host-read overlap probe of tb_freertos_axi after boot.
// Result      : ">>> TEST PASSED <<<" on success; any failure ends with
//               $fatal and a message (no PASS line is printed).
// ============================================================================
module tb_freertos_autoboot;
    localparam integer BOOT_BYTES = 16384;
    localparam logic [31:0] IMAGE_BASE = 32'h10001000;

    tb_freertos_axi #(.AUTOBOOT(1)) suite();
    reg [7:0] expected_bytes [0:BOOT_BYTES-1];
    integer writes = 0;
    integer mem_file;
    reg verified = 0;

    function automatic logic [31:0] expected_word(input integer word_index);
        integer byte_index;
        byte_index = word_index * 4;
        return {expected_bytes[byte_index + 3], expected_bytes[byte_index + 2],
                expected_bytes[byte_index + 1], expected_bytes[byte_index]};
    endfunction

    initial begin
        mem_file = $fopen("firmware.mem", "r");
        if (mem_file == 0)
            $fatal(1, "Missing autoboot firmware.mem");
        $fclose(mem_file);
        for (integer i = 0; i < BOOT_BYTES; ++i)
            expected_bytes[i] = 0;
        $readmemh("firmware.mem", expected_bytes);
        if (expected_word(0) !== 32'h30401073 ||
            expected_word(1024) === 32'h0)
            $fatal(1, "Expected FreeRTOS autoboot byte image");
    end

    always @(posedge suite.aclk) begin
        if (!suite.aresetn) begin
            writes = 0;
            verified = 0;
        end else if (!verified) begin
            if (suite.awvalid || suite.wvalid)
                $fatal(1, "Unexpected host write during cold boot");
            if (suite.uut.boot_mem_we) begin
                if (suite.uut.vrm_soc_inst.soc_cpu_rstn !== 1'b0)
                    $fatal(1, "CPU released during boot write");
                if (writes < BOOT_BYTES / 4) begin
                    if (suite.uut.boot_mem_addr !== IMAGE_BASE + 4*writes ||
                        suite.uut.boot_mem_wdata !== expected_word(writes))
                        $fatal(1, "Boot payload write %0d addr=%08x data=%08x",
                               writes, suite.uut.boot_mem_addr, suite.uut.boot_mem_wdata);
                end else if (writes == BOOT_BYTES / 4) begin
                    if (suite.uut.boot_mem_addr !== 32'h0 ||
                        suite.uut.boot_mem_wdata !== 32'h100012b7)
                        $fatal(1, "Incorrect reset LUI");
                end else if (writes == BOOT_BYTES / 4 + 1) begin
                    if (suite.uut.boot_mem_addr !== 32'h4 ||
                        suite.uut.boot_mem_wdata !== 32'h00028067)
                        $fatal(1, "Incorrect reset JALR");
                end else begin
                    $fatal(1, "Extra boot write");
                end
                writes = writes + 1;
            end
            if (!suite.uut.cpu_release &&
                suite.uut.vrm_soc_inst.soc_cpu_rstn !== 1'b0)
                $fatal(1, "CPU reset deasserted before boot release");
            if (suite.uut.cpu_release) begin
                if (!suite.uut.boot_done || writes != BOOT_BYTES / 4 + 2 ||
                    suite.uut.boot_mem_we || suite.uut.reg_cpu_ctrl[0] !== 1'b1 ||
                    suite.uut.vrm_soc_inst.soc_cpu_rstn !== 1'b1)
                    $fatal(1, "Boot release without complete load/reset sequencing");
                for (integer j = 0; j < BOOT_BYTES / 4; ++j)
                    if (suite.uut.vrm_soc_inst.ram[1024+j] !== expected_word(j))
                        $fatal(1, "Boot RAM mismatch at word %0d", j);
                if (suite.uut.vrm_soc_inst.ram[0] !== 32'h100012b7 ||
                    suite.uut.vrm_soc_inst.ram[1] !== 32'h00028067)
                    $fatal(1, "Reset trampoline missing from RAM alias");
                verified = 1;
                $display("AUTOBOOT checked %0d payload/padding words and 2 trampoline words; CPU released without AXI injection", BOOT_BYTES / 4);
            end
        end
    end
endmodule
