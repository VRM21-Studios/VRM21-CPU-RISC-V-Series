# 06 Validation

**Status: FPGA-validated** on a Kria KR260 for the tests below. Items that have
not been tested are listed at the end.

## Simulation

Command: `pwsh scripts/rv32im_freertos/run_sim.ps1` (Vivado Simulator 2025.2,
`xvlog` without `--relax`). A test passes only when its log contains
`>>> TEST PASSED <<<` and no `Fatal`, `[FAIL]`, `ERROR:`, watchdog, or
`readmem` message.

| Test | Testbench | Result | Key values |
| --- | --- | --- | --- |
| `freertos_autoboot` | `tb_freertos_autoboot` | PASS | see below; `$finish` at 86 193 160 ns |
| `freertos_host_overlap` | `tb_freertos_autoboot +host_overlap` | PASS | host CUTOFF read in the same cycle as a CPU store returns `0x2666`, TX counter 0 → 1 |
| `wfi_store` | `tb_rv32im_regression` | PASS | 0 stores executed while sleeping |
| `wfi_timer` | `tb_rv32im_regression` | PASS | one older and one younger store, none early; `mepc` = `0x48`, `mcause` = `0x8000_0007` |
| `wfi_timer_masked` | `tb_rv32im_regression` | PASS | wake with MIE = 0, no trap (`mepc` = `mcause` = 0) |
| `byte_enable` | `tb_rv32im_regression` | PASS | SB `1122a544`, LB `ffffffa5`, LBU `000000a5`, LH `ffffbeef`, LHU `0000beef`, SH+LW `beefa544`, sentinel `55667788` |

`freertos_autoboot` in detail:

| Phase | Result |
| --- | --- |
| Boot | 4096 image words and 2 trampoline words checked; no host write; CPU released after the last write |
| Scheduler, tick 40 | TX 3, RX 3, semaphore 3, idle 22, preemption 3, fault 0 |
| FX2 via GPIO | CTRL/CUTOFF readback; 16 filtered beats, 16 changed, 21 stall cycles, TLAST on beat 15; 8 host reads of CUTOFF = `0x1999` during the stream; commit applied |
| CLEAR via GPIO | bypass; 16 beats unchanged, 12 stall cycles |
| Warm reset (CPU_CTRL 0 → 1) | `.data`/`.bss` restored; tick 40 again with the same counters |
| MTIP latency during M-extension | DIV: 7 samples, maximum 59 cycles; REM: 21 samples, maximum 25 cycles |

The same testbenches were also run in Icarus Verilog 12.0 and Verilator
5.032 (`-O0`) with the same counters and checks; the Icarus `$finish` time of
`freertos_autoboot` is identical to the Vivado Simulator result.

## Implementation

Vivado 2025.2, part `xck26-sfvc784-2LV-c`, block design from
`scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl` (configuration as
implemented: `vrm_soc_axi_0` with `BOOT_FREERTOS = 1`, AXI DMA simple mode on
HP0/HP1, AXI GPIO 31 bits), one clock `clk_pl_0` at 100 MHz.

| Metric | Value |
| --- | --- |
| Synthesis | 0 errors, 0 critical warnings; `firmware.mem` read by the bootloader |
| WNS / TNS (setup) | +0.644 ns / 0.000 ns, 0 of 351 238 endpoints failing |
| WHS / THS (hold) | +0.010 ns / 0.000 ns |
| WPWS | +3.500 ns |
| `check_timing` | 0 unclocked, 0 unconstrained, 0 loops |
| Routing | 22 518 routable nets, all routed, 0 errors |
| CLB LUTs | 43 488 (37.1 %), of which distributed RAM 33 076 |
| Flip-flops | 7 367 (3.1 %) |
| Block RAM tiles | 6 (4.2 %) |
| DSP48E2 | 17 (1.4 %) |
| On-chip power | 2.837 W total, of which PS 2.419 W (estimate, medium confidence) |

The ten worst setup paths start at a forwarded operand (load data or ALU
result) and end in the multiplier result register of `vrm_mdu`; the worst
path has 19 logic levels and a 9.150 ns data path. The worst hold path is
inside the AXI GPIO IP. DRC and methodology reports contain warnings only
(DSP pipelining advisories, three LUTs driving asynchronous resets).

## Board

Board: Kria KR260 with PYNQ. The bitstream and the `.hwh` of the build above
were loaded by a PYNQ host application (not included in this repository),
which played a stereo 16-bit WAV file through AXI DMA and the VCF.

| Check | Result |
| --- | --- |
| Autoboot | marker `0x4652_5431`, fault 0, without any host loading |
| Scheduler after about 135 s | tick 135 290; TX 13 529, RX 13 529, semaphore 13 528, preemption 13 528, idle 54 124 |
| Audio | playback through the FPGA; no DMA fault |
| GPIO presets FX 1–6 | register readback matched for every preset; each filter audibly different |
| Commit | CTRL read `0x5` with bit 31 = 0 after the last preset (commit applied) |

## Not Yet Tested

- CLEAR (GPIO bit 0) on the board.
- Warm reset through CPU_CTRL and the host-read overlap probe on the board
  (both pass in simulation).
- Long-duration and temperature tests.
- Legacy boot mode (`BOOT_FREERTOS = 0`) on the board.
- The RISC-V architecture test suite; misaligned access behavior.
- Clock frequencies above 100 MHz.
