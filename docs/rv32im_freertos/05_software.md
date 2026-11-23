# 05 Software

## Firmware

The firmware in `gcc-firmware/rv32im_freertos/` is a FreeRTOS application
built with static allocation only.

| Task | Priority | Behavior |
| --- | --- | --- |
| TX (producer) | 2 | every 10 ticks sends a sequence number to a one-entry queue |
| RX (consumer) | 3 | receives, checks the sequence, gives a binary semaphore |
| REG (worker) | 1 | takes the semaphore, runs `context_probe` (register and DIV/REM check across context switches) |
| Idle | 0 | counts idle entries and executes WFI |

The GPIO interrupt handler applies VCF presets. The arbiter latches rising
edges of `ext_irq_in`; the handler serves CLEAR first, otherwise the lowest
preset number, and clears every latched FX bit.

| GPIO bit | Arbiter bit | Action | CTRL | CUTOFF | RES | LCO |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 1 | CLEAR: bypass, boot shadows | `0x00` | `0x2666` | `0x0CCC` | 15 |
| 1 | 2 | FX 1 low-pass | `0x05` | `0x2666` | `0x0CCC` | 15 |
| 2 | 3 | FX 2 high-pass | `0x0D` | `0x1999` | `0x0CCC` | 15 |
| 3 | 4 | FX 3 band-pass | `0x15` | `0x2000` | `0x2666` | 15 |
| 4 | 5 | FX 4 resonant low-pass | `0x05` | `0x3333` | `0x6666` | 20 |
| 5 | 6 | FX 5 bright high-pass | `0x0D` | `0x1333` | `0x4000` | 18 |
| 6 | 7 | FX 6 vocal band-pass | `0x15` | `0x1999` | `0x4CCC` | 18 |

CTRL values are shown without bit 31 (commit pending).

### Diagnostic block (`0x1000_F000`)

| Word | Content |
| --- | --- |
| 0 | marker `0x4652_5431` ("FRT1") after start-up |
| 1 | tick count |
| 2 | messages sent (TX) |
| 3 | messages received (RX) |
| 4 | semaphore/probe completions |
| 5 | idle entries |
| 6 | preemptions observed while the probe runs |
| 7 | fault code (0 = none) |

Fault codes written by `firmware_fault`: 1 assertion, 2 return from main,
3 queue send, 4 receive or sequence error, 5 semaphore give, 6 semaphore
take, 7 context probe failure, 8 scheduler returned, 9 `.data`/`.bss`
start-up check; `0x100 | cause` for an unexpected exception and the raw
`mcause` for an unexpected interrupt.

## FreeRTOS Port

The kernel is FreeRTOS V11.1.0 (git submodule `FreeRTOS-Kernel`, commit
`dbf70559b27d39c1fdb68dfb9a32140b6a6777a0`), using `tasks.c`, `list.c`,
`queue.c`, and the GCC RISC-V port with `chip_specific_extensions/RISCV_no_extensions`.
The SoC has no `mtime`/`mtimecmp`, so `configMTIME_BASE_ADDRESS` and
`configMTIMECMP_BASE_ADDRESS` are 0 and `port_vrm.c` provides:

- `vPortSetupTimerInterrupt`: local timer with auto-reload at 1 kHz
  (`configCPU_CLOCK_HZ` 100 MHz), MTIE and MEIE enabled, FX arbiter bits
  enabled.
- `freertos_risc_v_application_interrupt_handler`: MTIP acknowledges the timer,
  increments the tick, and yields when required; MEIP calls the GPIO/VCF
  handler.
- `freertos_risc_v_application_exception_handler`: records a fault code.

The kernel files are used unmodified.

## Build

Requirements: GNU Make, Python 3, and a bare-metal RISC-V GCC 12 or newer
(`-march=rv32im_zicsr`, `-Oz`). The published image was built with GCC 14.2.0.

```text
git submodule update --init
cd gcc-firmware/rv32im_freertos
make                      # or: make OUT=build CROSS=riscv32-unknown-elf-
cp firmware.mem ../../include/rv32im_freertos/firmware.mem
```

`make` runs `scripts/rv32im_freertos/check_boot_image.py`, which checks that
the ELF entry is `0x1000_1000`, that the ELF load segments equal the BIN,
that the image fits in 16 KiB, and that `firmware.mem` equals the BIN.

The directed test programs are rebuilt with
`scripts/rv32im_freertos/build_tb_programs.sh`.

## Host Contract

A host (for example a PYNQ application on the Zynq UltraScale+ PS) uses:

- the AXI4-Lite window of `vrm_soc_axi_0` for VCF register reads, CPU_CTRL,
  RAM reads (diagnostic block), and image loading;
- AXI DMA in simple mode for audio, arming S2MM before MM2S, with buffers
  below 4 GB (the DMA address width is 32 bits);
- AXI GPIO channel 1 (31 outputs) to request presets, by writing a
  0 → 1 → 0 pulse on one bit.

The host should not write VCF registers while the firmware may write them
from the GPIO handler; requesting presets through GPIO keeps the firmware the
only writer. Host reads of any register are always safe. No host
application is included in this repository.
