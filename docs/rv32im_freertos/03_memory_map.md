# 03 Memory Map

The RTL definitions are in `include/rv32im_freertos/vrm_soc_map_rv32i.vh`; the
firmware uses the same values in `gcc-firmware/rv32im_freertos/soc_map.h`.

## CPU View

| Address range | Block | Notes |
| --- | --- | --- |
| `0x0000_0000`–`0x0000_0FFF` | ROM window | alias of RAM `0x1000_0000`–`0x1000_0FFF`; reset vector 0 |
| `0x1000_0000`–`0x1000_FFFF` | RAM, 64 KiB | unified code and data |
| `0x4000_0000`–`0x4000_00FF` | Timer | CTRL, COMPARE, COUNTER, STATUS |
| `0x4000_1000`–`0x4000_10FF` | Interrupt arbiter | PENDING, ENABLE, CLEAR |
| `0x8000_1000`–`0x8000_10FF` | Reserved | oscillator window, not decoded |
| `0x8000_2000`–`0x8000_20FF` | VCF | CTRL, CUTOFF, RES, LCO |

An instruction fetch outside ROM and RAM returns `0x0000_0000` and traps as
an illegal instruction.

### RAM use by the FreeRTOS firmware

| Range | Use |
| --- | --- |
| `0x1000_0000`–`0x1000_0007` | reset trampoline (also visible at `0x0`/`0x4`) |
| `0x1000_1000`–`0x1000_4FFF` | autoboot image slot (16 KiB), code and `.data` load image |
| `0x1000_6000`–`0x1000_EFFF` | `.data`, `.bss`, static task stacks |
| `0x1000_F000`–`0x1000_F01F` | diagnostic block (see [05_software.md](05_software.md)) |
| up to `0x1001_0000` | startup and interrupt stack (top) |

## Timer (`0x4000_0000`)

| Offset | Register | Fields |
| --- | --- | --- |
| `0x00` | CTRL | [0] enable, [1] auto-reload to 0, [2] interrupt enable |
| `0x04` | COMPARE | match value, reset `0xFFFF_FFFF` |
| `0x08` | COUNTER | running count |
| `0x0C` | STATUS | [0] pending, write 1 to clear |

STATUS[0] is set when COUNTER ≥ COMPARE; with auto-reload the period is
COMPARE + 1 cycles. The FreeRTOS port uses COMPARE = 99 999 for a 1 kHz tick
at 100 MHz.

## Interrupt Arbiter (`0x4000_1000`)

| Offset | Register | Fields |
| --- | --- | --- |
| `0x00` | PENDING | latched rising edges, read-only |
| `0x04` | ENABLE | per-source enable |
| `0x08` | CLEAR | write 1 to clear PENDING bits |

Bit 0 is the timer, bits 1..31 are `ext_irq_in[0..30]`. In the reference
block design the external inputs come from a 31-bit AXI GPIO.

## VCF (`0x8000_2000`)

| Offset | Register | Fields |
| --- | --- | --- |
| `0x00` | CTRL | W: [0] enable, [2] commit arm, [4:3] type (0 LP, 1 HP, 2 BP). R: same, plus [31] commit pending |
| `0x04` | CUTOFF | Q1.15 shadow (reset `0x4000`) |
| `0x08` | RES | Q1.15 shadow (reset `0x0800`) |
| `0x0C` | LCO | unsigned shadow (reset 15) |

Write CUTOFF, RES, and LCO first and CTRL with bit 2 set last. Every write
cancels a pending commit. Offsets `0x10`–`0x3C` read 0; offsets from `0x40`
alias onto `0x00`–`0x3C`.

## Host View (AXI4-Lite)

The host reaches the SoC through one AXI4-Lite slave. The slave decodes the
full 32-bit offset inside its window, so the window must cover at least
`0x8000_2010`; the reference block design assigns 4 GB at `0x4_0000_0000`.

| Offset | Target |
| --- | --- |
| `0x0000_0000`–`0x0000_0FFF` | ROM window (RAM alias) |
| `0x0000_C000` | CPU_CTRL: [0] 0 = hold CPU in reset, 1 = run (reset value 1) |
| `0x1000_0000`–`0x1000_FFFF` | RAM |
| `0x8000_2000`–`0x8000_200C` | VCF registers |

Notes:

- Host writes are full words; WSTRB is ignored.
- WARNING: CPU_CTRL is matched on offset bits [15:0] only. A host write to
  any offset whose low 16 bits are `0xC000` (for example RAM `0x1000_C000`)
  changes CPU_CTRL instead of memory.
- Timer and arbiter registers are not reachable from the host.
