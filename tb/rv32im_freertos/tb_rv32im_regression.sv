`timescale 1ns / 1ps
// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// Testbench   : tb_rv32im_regression
// Description : Directed core regression on vrm_soc_top with the stand-alone
//               bootloader. Each test runs a small assembly program from
//               tb/rv32im_freertos/programs, built to firmware.mem.
//                 wfi_store        : no store younger than WFI executes while
//                                    the core sleeps without a wake source.
//                 wfi_timer        : MTIP wakes WFI with MIE = 1; one older
//                                    and one younger store, none early;
//                                    mepc = instruction after WFI, mcause =
//                                    0x8000_0007.
//                 wfi_timer_masked : same wake with MIE = 0; no trap taken.
//                 byte_enable      : SB/SH keep neighbouring lanes; LB/LBU/
//                                    LH/LHU extension; adjacent SW sentinel.
//               Expected values are the constants in the checks below.
// Parameters  : +test=<name> selects the test. firmware.mem of that test must
//               be in the simulator run directory. Watchdog: 2500 cycles.
// Result      : ">>> TEST PASSED <<<" on success; failures print "[FAIL]"
//               and end with $fatal.
// ============================================================================
module tb_rv32im_regression;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    wire boot_mem_we, boot_done, cpu_release, cpu_halt;
    wire [31:0] boot_mem_addr, boot_mem_wdata, cpu_pc;
    integer timer_stores = 0;
    integer early_timer_stores = 0;
    integer older_stores = 0;
    integer failures = 0;
    wire timer_irq = dut.cpu_sys_inst.timer_irq;
    reg saw_timer_irq = 1'b0;
    reg saw_halt = 1'b0;
    string test_name;

    always #5 clk = ~clk;

    vrm_bootloader boot (
        .clk(clk), .rstn(rstn),
        .boot_mem_we(boot_mem_we), .boot_mem_addr(boot_mem_addr),
        .boot_mem_wdata(boot_mem_wdata), .boot_done(boot_done), .cpu_release(cpu_release)
    );

    vrm_soc_top dut (
        .clk(clk), .sys_rstn(rstn), .rstn(rstn),
        .host_we(1'b0), .host_re(1'b0), .host_addr(32'd0),
        .host_wdata(32'd0), .host_rdata(), .ext_irq_in(31'd0),
        .boot_mem_we(boot_mem_we), .boot_mem_addr(boot_mem_addr),
        .boot_mem_wdata(boot_mem_wdata), .boot_done(boot_done), .cpu_release(cpu_release),
        .s_axis_tdata(32'd0), .s_axis_tvalid(1'b0), .s_axis_tlast(1'b0), .s_axis_tready(),
        .m_axis_tdata(), .m_axis_tvalid(), .m_axis_tlast(), .m_axis_tready(1'b1),
        .cpu_halt(cpu_halt), .cpu_pc(cpu_pc), .debug_reg_x1()
    );

    always @(posedge clk) begin
        if (rstn && cpu_release) begin
            if (cpu_halt)
                saw_halt <= 1'b1;
            if (timer_irq)
                saw_timer_irq <= 1'b1;
            if (dut.cpu_sys_inst.sys_timer.we &&
                dut.cpu_sys_inst.cpu_mem_addr == 32'h40000000 &&
                dut.cpu_sys_inst.cpu_mem_wdata == 32'h00000123) begin
                timer_stores <= timer_stores + 1;
                if (!timer_irq && !saw_timer_irq)
                    early_timer_stores <= early_timer_stores + 1;
            end
            if (dut.cpu_mem_we && dut.cpu_mem_addr == 32'h10001008)
                older_stores <= older_stores + 1;
        end
    end

    task check_word(input integer offset, input logic [31:0] expected, input string name);
        logic [31:0] actual;
        begin
            actual = dut.ram[1024 + offset / 4];
            if (actual !== expected) begin
                $display("[FAIL] %s got=%08h expected=%08h", name, actual, expected);
                failures = failures + 1;
            end else begin
                $display("[PASS] %s got=%08h", name, actual);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("test=%s", test_name))
            $fatal(1, "test plusarg is required");
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        wait (cpu_release === 1'b1);
        @(negedge clk);
        if (dut.ram[0] !== (test_name == "byte_enable" ? 32'h100012b7 : 32'h400002b7))
            $fatal(1, "Firmware marker mismatch: %08h", dut.ram[0]);

        if (test_name == "wfi_store") begin
            wait (cpu_halt === 1'b1);
            repeat (64) @(negedge clk);
            $display("WFI_NO_IRQ timer writes of 0x123=%0d while sleeping; PC=%08h",
                     timer_stores, cpu_pc);
            if (cpu_halt !== 1'b1 || timer_stores != 0)
                $fatal(1, "[FAIL] younger SW had a side effect before wake");
        end else if (test_name == "wfi_timer" || test_name == "wfi_timer_masked") begin
            wait (dut.ram[1035] === 32'hdeadbeef || dut.ram[1035] === 32'h00000bad);
            repeat (64) @(negedge clk);
            $display("WFI_TIMER halted=%0b irq=%0b older stores=%0d younger stores=%0d early=%0d",
                     saw_halt, saw_timer_irq, older_stores, timer_stores, early_timer_stores);
            check_word(44, 32'hdeadbeef, "post-wake load/branch/CSR path");
            if (test_name == "wfi_timer") begin
                check_word(0, dut.ram[1027], "mepc points to instruction after WFI");
                check_word(4, 32'h80000007, "MTIP trap cause");
            end else begin
                check_word(0, 32'd0, "MIE=0 leaves trap PC untouched");
                check_word(4, 32'd0, "MIE=0 wakes without trapping");
            end
            if (failures != 0 || !saw_halt || !saw_timer_irq || cpu_halt ||
                older_stores != 1 || timer_stores != 1 || early_timer_stores != 0)
                $fatal(1, "[FAIL] WFI timer wake or store ordering");
        end else if (test_name == "byte_enable") begin
            wait (dut.ram[1035] === 32'hdeadbeef);
            @(negedge clk);
            check_word(16, 32'h1122a544, "SB preserves three lanes");
            check_word(20, 32'hffffffa5, "LB sign extension");
            check_word(24, 32'h000000a5, "LBU zero extension");
            check_word(28, 32'hffffbeef, "LH sign extension");
            check_word(32, 32'h0000beef, "LHU zero extension");
            check_word(36, 32'hbeefa544, "SH preserves other half and LW reads word");
            check_word(40, 32'h55667788, "SW adjacent sentinel survives");
            if (failures != 0)
                $fatal(1, "[FAIL] %0d byte-enable checks", failures);
        end else begin
            $fatal(1, "Unknown test %s", test_name);
        end
        $display(">>> TEST PASSED <<<");
        $finish;
    end

    initial begin
        repeat (2500) @(posedge clk);
        $fatal(1, "Regression watchdog expired PC=%08h", cpu_pc);
    end
endmodule
