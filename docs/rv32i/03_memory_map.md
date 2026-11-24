# VRM RV32I CPU — Memory Map

## 1. Overview

The VRM RV32I SoC uses a simple memory-mapped architecture.

The address space is divided into:

1. Tier 0: system memory (boot ROM and system RAM)
2. Tier 1: system core peripherals (hardware timer and interrupt arbiter)
3. Tier 2: application-specific accelerator space

The current system map is defined in:

```text
include/rv32i/vrm_soc_map_rv32i.vh
```

The software-visible version is:

```text
gcc-firmware/rv32i/soc_map.h
```

Both definitions are intended to remain synchronized.

---

## 2. Address Map

| Address Range               |  Size | Tier | Device                          | Access          |
| --------------------------- | ----: | ---- | ------------------------------- | --------------- |
| `0x0000_0000 - 0x0000_0FFF` |  4 KB | 0    | Boot ROM                        | R (boot image)  |
| `0x1000_0000 - 0x1000_FFFF` | 64 KB | 0    | System RAM                      | R/W             |
| `0x4000_0000 - 0x4000_00FF` | 256 B | 1    | Hardware Timer                  | MMIO            |
| `0x4000_1000 - 0x4000_10FF` | 256 B | 1    | Interrupt Arbiter               | MMIO            |
| From `0x8000_0000`          |     — | 2    | Application / Accelerator Space | Project-defined |

The CPU wrapper decodes only the timer and interrupt-arbiter windows. Every
other address is forwarded to the external memory interface, where the
integrating SoC places the boot ROM, the system RAM, and any accelerator.

---

## 3. Boot ROM and System RAM

Boot ROM:

```text
Base : 0x0000_0000
Size : 4 KB
```

The CPU starts at `0x0000_0000` after reset and takes machine-mode interrupts
at `0x0000_0004`, so the boot image must provide both vectors at the start of
this window.

System RAM:

```text
Base : 0x1000_0000
Size : 64 KB
End  : 0x1001_0000
```

The firmware linker script (`gcc-firmware/rv32i/link.ld`) links the complete
firmware image from address `0x0000_0000`:

```text
RAM ORIGIN = 0x00000000
RAM LENGTH = 0x00010000
_stack_top = ORIGIN(RAM) + LENGTH(RAM) = 0x0001_0000
```

NOTE: the linked image and its stack therefore occupy `0x0000_0000` to
`0x0000_FFFF`. The integrating SoC must provide memory over this range, for
example by mapping the 64 KB system RAM array behind both windows. An
integration that only maps the 4 KB boot ROM window at `0x0000_0000` must
reduce `LENGTH` in the linker script so that the stack stays inside that
window.

---

## 4. Hardware Timer

Base address:

```text
0x4000_0000
```

Register layout:

| Offset | Address       | Register | Access | Description      |
| -----: | ------------- | -------- | ------ | ---------------- |
| `0x00` | `0x4000_0000` | CTRL     | R/W    | Timer control    |
| `0x04` | `0x4000_0004` | COMPARE  | R/W    | Compare value    |
| `0x08` | `0x4000_0008` | COUNTER  | R/W    | Current counter  |
| `0x0C` | `0x4000_000C` | STATUS   | R/W1C  | Interrupt status |

---

## 5. Timer CTRL

Address:

```text
0x4000_0000
```

Bit definitions:

|  Bit | Name        | Description                   |
| ---: | ----------- | ----------------------------- |
|    0 | EN          | Timer enable                  |
|    1 | AUTO_RELOAD | Reset counter after compare   |
|    2 | IRQ_EN      | Enable timer interrupt output |
| 31:3 | Reserved    | Not used                      |

The timer interrupt output is asserted when:

```text
CTRL[2] && STATUS[0]
```

---

## 6. Timer COMPARE

Address:

```text
0x4000_0004
```

The compare register determines when the timer reaches its interrupt condition.

The timer continuously increments while enabled.

When:

```text
COUNTER >= COMPARE
```

the timer sets:

```text
STATUS[0] = 1
```

If auto-reload is enabled, the counter is reset to zero.

---

## 7. Timer COUNTER

Address:

```text
0x4000_0008
```

This register contains the current timer count.

Software may write to this register to manually change or reset the counter.

---

## 8. Timer STATUS

Address:

```text
0x4000_000C
```

Current status bits:

|  Bit | Name        | Description             |
| ---: | ----------- | ----------------------- |
|    0 | IRQ_PENDING | Timer interrupt pending |
| 31:1 | Reserved    | Not used                |

The status register uses Write-One-to-Clear semantics.

Example:

```c
TIMER_STATUS = 1;
```

clears the pending interrupt flag.

---

## 9. Interrupt Arbiter

Base address:

```text
0x4000_1000
```

The interrupt arbiter collects multiple interrupt sources and provides a single interrupt signal to the CPU.

Current source assignment:

```text
irq_src[0]    = Timer
irq_src[31:1] = External / Future Sources
```

Register layout:

| Offset | Address       | Register | Access | Description               |
| -----: | ------------- | -------- | ------ | ------------------------- |
| `0x00` | `0x4000_1000` | PENDING  | R      | Pending interrupt sources |
| `0x04` | `0x4000_1004` | ENABLE   | R/W    | Interrupt enable mask     |
| `0x08` | `0x4000_1008` | CLEAR    | W1C    | Interrupt acknowledge     |

---

## 10. Interrupt Pending Register

Address:

```text
0x4000_1000
```

The arbiter detects rising edges from the interrupt sources.

A source transition:

```text
0 -> 1
```

sets the corresponding pending bit.

Once set, the pending bit remains asserted until software clears it through
the CLEAR register.

---

## 11. Interrupt Enable Register

Address:

```text
0x4000_1004
```

Each bit controls whether the corresponding pending interrupt source can reach the CPU.

For each source:

```text
IRQ_ACTIVE = PENDING & ENABLE
```

The CPU interrupt output is asserted when at least one enabled pending interrupt exists:

```text
cpu_irq_trigger = |(pending & enable)
```

---

## 12. Interrupt Clear Register

Address:

```text
0x4000_1008
```

The clear register uses Write-One-to-Clear semantics.

Writing:

```text
0x00000001
```

clears the timer interrupt pending bit.

Writing:

```text
0xFFFFFFFF
```

clears all pending interrupt sources.

---

## 13. External Interrupt Inputs

The wrapper exposes:

```text
ext_irq_in[30:0]
```

These signals are mapped into the arbiter as:

```text
irq_sources[31:1] = ext_irq_in
```

The timer occupies bit 0.

Therefore:

```text
IRQ source 0  = Timer
IRQ source 1  = External IRQ 0
IRQ source 2  = External IRQ 1
...
IRQ source 31 = External IRQ 30
```

---

## 14. External Memory / Accelerator Space

Addresses outside the timer and interrupt-arbiter regions are routed to the external memory interface.

The wrapper performs local address decoding:

```text
timer_sel
arbiter_sel
```

If neither peripheral is selected:

```text
cpu_mem_rdata = ext_mem_rdata
```

and external writes are enabled when:

```text
ext_mem_we = cpu_mem_we
```

provided that the address is not mapped to a local peripheral.

This allows additional hardware blocks to be connected without modifying the CPU core itself.

---

## 15. Address Decode

The wrapper determines peripheral selection using address ranges.

Timer:

```text
TIMER_BASE_ADDR <= address < TIMER_END_ADDR      (0x4000_0000 .. 0x4000_00FF)
```

Interrupt arbiter:

```text
IRQ_BASE_ADDR <= address < IRQ_END_ADDR          (0x4000_1000 .. 0x4000_10FF)
```

All other addresses are routed externally.

---

## 16. Software Address Definitions

The software header provides equivalent definitions:

```c
#define TIMER_BASE      0x40000000UL
#define TIMER_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x00UL))
#define TIMER_COMPARE   (*(volatile uint32_t *)(TIMER_BASE + 0x04UL))
#define TIMER_COUNTER   (*(volatile uint32_t *)(TIMER_BASE + 0x08UL))
#define TIMER_STATUS    (*(volatile uint32_t *)(TIMER_BASE + 0x0CUL))

#define IRQ_BASE        0x40001000UL
#define IRQ_PENDING     (*(volatile uint32_t *)(IRQ_BASE + 0x00UL))
#define IRQ_ENABLE      (*(volatile uint32_t *)(IRQ_BASE + 0x04UL))
#define IRQ_CLEAR       (*(volatile uint32_t *)(IRQ_BASE + 0x08UL))
```

The registers are declared `volatile` because they represent hardware state rather than ordinary memory.

---

## 17. Future Expansion

The memory map reserves the Tier 2 address space, starting at `0x8000_0000`,
for application-specific hardware.

Potential devices include:

* DSP cores
* FIFO controllers
* RAM controllers
* FFT accelerators
* DWT accelerators
* NPU interfaces
* AXI-connected application peripherals

New accelerator windows are added to the Tier 2 section of both
`vrm_soc_map_rv32i.vh` and `soc_map.h` without changing the Tier 0 or Tier 1
map.
