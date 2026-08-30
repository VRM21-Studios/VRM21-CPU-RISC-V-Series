# RV64IMFD Memory System

## 1. Overview

The RV64IMFD processor uses a 64-bit data-memory interface.

The interface consists of:

```text
mem_addr
mem_wdata
mem_we
mem_wstrb
mem_rdata
mem_busy
```

The design supports byte-addressable loads and stores over a 64-bit data path.

---

## 2. Address Generation

Load and store addresses are calculated in the EX stage.

For an address-based operation:

```text
effective_address = base_register + immediate
```

The resulting address is forwarded to:

```text
mem_addr
```

---

## 3. Write Data

Store data is selected from:

- Integer register file for integer stores
- Floating-point register file for floating-point stores

The CPU determines the source from the instruction opcode.

---

## 4. Write Strobes

The processor provides an 8-bit byte strobe:

```text
mem_wstrb[7:0]
```

Each bit represents one byte lane of the 64-bit data bus.

The basic store widths are:

| Instruction | Width | Base Strobe |
|---|---:|---|
| SB / FSB | 8-bit | `0000_0001` |
| SH / FSH | 16-bit | `0000_0011` |
| SW / FSW | 32-bit | `0000_1111` |
| SD / FSD | 64-bit | `1111_1111` |

The strobe is shifted according to the address offset.

---

## 5. Store Data Replication

The CPU replicates narrow store values across the 64-bit bus.

For example, a byte store is represented internally as repeated copies of the selected byte.

The external memory system uses the byte strobe to determine which physical byte lane is written.

---

## 6. Load Alignment

The memory return value is shifted according to:

```text
mem_wb_alu_res[2:0]
```

This extracts the requested byte/half-word/word/double-word from the 64-bit memory response.

---

## 7. Load Extension

The processor supports:

```text
LB
LBU
LH
LHU
LW
LWU
LD
```

Signed loads are sign-extended.

Unsigned loads are zero-extended.

---

## 8. Memory Busy

External memory can indicate that a transaction remains active through:

```text
mem_busy
```

When asserted, the CPU prevents pipeline advancement where required.

The wrapper treats local peripheral accesses separately from external memory accesses.

---

## 9. Local MMIO

The CPU wrapper contains address decoding for local peripherals.

Current local regions include:

```text
Timer
Interrupt Arbiter
```

Local accesses do not depend on the external memory busy signal.

---

## 10. External Memory

Non-local accesses are forwarded to the external memory interface.

The wrapper exposes:

```text
ext_mem_addr
ext_mem_wdata
ext_mem_wstrb
ext_mem_we
ext_mem_rdata
ext_mem_busy
```

This interface can subsequently be connected to a RAM controller, AXI bridge, or other memory subsystem.

---

## 11. Memory Map

The current memory map is defined by:

```text
vrm_soc_map_rv64.vh
```

Current regions include:

```text
0x0000_0000_0000_0000
    Timer

0x0000_0000_0000_1000
    Interrupt Arbiter

0x0000_0000_0000_4000
    Main RAM

0x0000_0000_4000_0000
    Reserved accelerator region
```

The exact end addresses and peripheral register offsets are defined in the SoC map header.

---

## 12. Current Status

The memory interface and alignment logic are implemented.

Verification of unaligned accesses, memory wait states, and interactions between pipeline stalls and external memory remains part of the ongoing verification process.