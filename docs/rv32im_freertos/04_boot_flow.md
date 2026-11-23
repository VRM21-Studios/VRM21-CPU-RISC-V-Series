# 04 Boot Flow

## Autoboot (default, `BOOT_FREERTOS = 1`)

```text
s_axi_aresetn low
      │
      ▼
vrm_bootloader: 4096 words of firmware.mem → RAM 0x1000_1000 … 0x1000_4FFC
      │         (one word per clock; bytes beyond the image are 0)
      ▼
reset trampoline → 0x0000_0000: lui  t0, 0x10001
                   0x0000_0004: jalr x0, 0(t0)
      │
      ▼
boot_done, cpu_release → CPU leaves reset at PC 0 → jumps to 0x1000_1000
      │
      ▼
boot.S: mask interrupts, set sp/gp/tp, mtvec (direct), copy .data, clear .bss
      │
      ▼
main(): diagnostics, VCF bypass, queue/semaphore, three tasks, scheduler
```

The image is `include/rv32im_freertos/firmware.mem`, a byte-per-token hex file
(`objcopy -O verilog`) whose offsets are relative to `0x1000_1000`. Its
first word is `csrw mie, zero` (`0x3040_1073`). The slot is 16 KiB; the
current image uses 7552 bytes. In simulation the file must be in the
simulator run directory; in Vivado synthesis it must be a design source named
`firmware.mem`.

The CPU stays in reset during every bootloader write; the testbench
`tb_freertos_autoboot` checks the address and data of all 4096 words, the two
trampoline words, and the release order.

## Warm Reset

Writing CPU_CTRL = 0 and then 1 restarts the CPU at PC 0 without reloading
RAM. The trampoline and the image are still present, so the firmware starts
again from `boot.S`, which restores `.data` from its load image and clears
`.bss`. The testbench checks that the scheduler reaches tick 40 again after a
warm reset.

An external reset (`s_axi_aresetn`) reruns the bootloader and restores the
original image, including any RAM contents that the host had changed.

## Legacy Mode (`BOOT_FREERTOS = 0`)

The bootloader copies a 4 KiB image to `0x0000_0000` and writes no trampoline.
This mode is used by `tb_freertos_axi` with `AUTOBOOT = 0`: a seed image
(`gcc-firmware/rv32im_freertos/boot_wait.S`, an endless WFI loop) boots first,
then the testbench holds the CPU, loads the FreeRTOS payload over AXI4-Lite
to `0x1000_1000`, writes the same trampoline at `0x0`/`0x4`, and releases the
CPU.

## Loading a New Image from the Host

1. Write CPU_CTRL = 0.
2. Write the image words (little-endian) to `0x1000_1000 + 4·i`.
3. Make sure `0x0`/`0x4` hold the trampoline.
4. Write CPU_CTRL = 1.

The image must fit below `0x1000_5000` (16 KiB) and must not use RAM offsets
whose low 16 bits are `0xC000` for host writes (see
[03_memory_map.md](03_memory_map.md)).
