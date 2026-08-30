# VRM RV32I CPU — Memory Map

## 1. Overview

The VRM RV32I SoC uses a simple memory-mapped architecture.

The processor's data address space is divided into:

1. System RAM
2. Hardware Timer
3. Interrupt Arbiter
4. Application and accelerator space

The current system map is defined in:

```text
vrm_soc_map_rv32i.vh
```

The software-visible version is:

```text
soc_map.h
```

Both definitions are intended to remain synchronized.

---

## 2. Address Map

| Address Range               |  Size | Device                          | Access          |
| --------------------------- | ----: | ------------------------------- | --------------- |
| `0x0000_0000 - 0x0000_0FFF` |  4 KB | System RAM                      | R/W             |
| `0x0000_1000 - 0x0000_10FF` | 256 B | Hardware Timer                  | MMIO            |
| `0x0000_2000 - 0x0000_20FF` | 256 B | Interrupt Arbiter               | MMIO            |
| Above `0x0000_2100`         |     — | Application / Accelerator Space | Project-defined |

---

## 3. System RAM

Base address:

```text
0x0000_0000
```

Size:

```text
4 KB
```

End address:

```text
0x0000_1000
```

The RAM is used for:

* Program code
* Read-only data
* Writable data
* BSS
* Stack

The linker script therefore defines:

```text
RAM ORIGIN = 0x00000000
RAM LENGTH = 0x1000
```

The initial stack pointer is placed at:

```text
0x0000_1000
```

---

## 4. Hardware Timer

Base address:

```text
0x0000_1000
```

Register layout:

| Offset | Register | Access | Description      |
| -----: | -------- | ------ | ---------------- |
| `0x00` | CTRL     | R/W    | Timer control    |
| `0x04` | COMPARE  | R/W    | Compare value    |
| `0x08` | COUNTER  | R/W    | Current counter  |
| `0x0C` | STATUS   | R/W1C  | Interrupt status |

---

## 5. Timer CTRL

Address:

```text
0x0000_1000
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
0x0000_1004
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
0x0000_1008
```

This register contains the current timer count.

Software may write to this register to manually change or reset the counter.

---

## 8. Timer STATUS

Address:

```text
0x0000_100C
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
0x0000_2000
```

The interrupt arbiter collects multiple interrupt sources and provides a single interrupt signal to the CPU.

Current source assignment:

```text
irq_src[0]    = Timer
irq_src[31:1] = External / Future Sources
```

Register layout:

| Offset | Register | Access | Description               |
| -----: | -------- | ------ | ------------------------- |
| `0x00` | PENDING  | R/W1C  | Pending interrupt sources |
| `0x04` | ENABLE   | R/W    | Interrupt enable mask     |
| `0x08` | CLEAR    | W1C    | Interrupt acknowledge     |

---

## 10. Interrupt Pending Register

Address:

```text
0x0000_2000
```

The arbiter detects rising edges from the interrupt sources.

A source transition:

```text
0 -> 1
```

sets the corresponding pending bit.

Once set, the pending bit remains asserted until software clears it.

---

## 11. Interrupt Enable Register

Address:

```text
0x0000_2004
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
0x0000_2008
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
TIMER_BASE_ADDR <= address < TIMER_END_ADDR
```

Interrupt arbiter:

```text
IRQ_BASE_ADDR <= address < IRQ_END_ADDR
```

All other addresses are routed externally.

---

## 16. Software Address Definitions

The software header provides equivalent definitions:

```c
#define TIMER_BASE      0x00001000
#define TIMER_CTRL      (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIMER_COMPARE   (*(volatile uint32_t*)(TIMER_BASE + 0x04))
#define TIMER_COUNTER   (*(volatile uint32_t*)(TIMER_BASE + 0x08))
#define TIMER_STATUS    (*(volatile uint32_t*)(TIMER_BASE + 0x0C))

#define IRQ_BASE        0x00002000
#define IRQ_PENDING     (*(volatile uint32_t*)(IRQ_BASE + 0x00))
#define IRQ_ENABLE      (*(volatile uint32_t*)(IRQ_BASE + 0x04))
#define IRQ_CLEAR       (*(volatile uint32_t*)(IRQ_BASE + 0x08))
```

The registers are declared `volatile` because they represent hardware state rather than ordinary memory.

---

## 17. Future Expansion

The memory map reserves higher address space for application-specific hardware.

Potential devices include:

* DSP cores
* Audio processing blocks
* FIFO controllers
* RAM controllers
* FFT accelerators
* DWT accelerators
* NPU interfaces
* AXI-connected application peripherals

The current architecture intentionally leaves these regions open for future SoC expansion.
