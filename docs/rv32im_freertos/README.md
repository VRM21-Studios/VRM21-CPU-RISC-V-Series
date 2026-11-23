# RV32IM + FreeRTOS Variant

**Repository profile:** C (Integrated SoC). This variant combines an RV32IM
processor, a stereo state-variable filter (VCF) on an AXI4-Stream audio path,
and a FreeRTOS firmware that boots automatically from on-chip RAM on a
Kria KR260.

**Validation status:** FPGA-validated on the Kria KR260 for the tests listed in
[06_validation.md](06_validation.md), which also lists what has not been tested.

## Overview

The variant extends the RV32I baseline of this series in three directions.
The core adds the M extension (multiply and divide) and machine-mode traps for
illegal instructions, ECALL, and EBREAK, so that a preemptive real-time kernel
can run on it. The SoC places a 64 KiB unified RAM, a local timer, an interrupt
arbiter, and a stereo filter behind one AXI4-Lite slave and one AXI4-Stream
path, so that a Zynq UltraScale+ host can stream audio through the filter
while the CPU changes filter presets in response to interrupts. A hardware
bootloader copies the FreeRTOS image into RAM at reset and releases the CPU
without any action from the host.

## Documents

| File | Content |
| --- | --- |
| [01_architecture.md](01_architecture.md) | Pipeline, SoC structure, buses, VCF datapath |
| [02_instruction_set.md](02_instruction_set.md) | Supported instructions, CSRs, traps, interrupts, WFI |
| [03_memory_map.md](03_memory_map.md) | CPU map, host (AXI4-Lite) map, register maps |
| [04_boot_flow.md](04_boot_flow.md) | Autoboot, reset trampoline, warm reset, legacy mode |
| [05_software.md](05_software.md) | Firmware, FreeRTOS port, build, host contract |
| [06_validation.md](06_validation.md) | Simulation, implementation, board results, open items |

## Source Layout

```text
rtl/rv32im_freertos/            synthesizable RTL (top: vrm_soc_axi)
include/rv32im_freertos/        vrm_soc_map_rv32i.vh, firmware.mem (boot image)
tb/rv32im_freertos/             testbenches, programs/*.S, mem/*.mem
gcc-firmware/rv32im_freertos/   FreeRTOS application and port
                                FreeRTOS-Kernel/ (git submodule)
scripts/rv32im_freertos/        run_sim.ps1, build_tb_programs.sh,
                                check_boot_image.py, vrm_rv32im_freertos_bd.tcl
```

## Quick Start

```text
git submodule update --init                      # FreeRTOS kernel (firmware build only)
pwsh scripts/rv32im_freertos/run_sim.ps1         # XSim regression, exit 0 = all PASS
```

In Vivado, `source scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl` creates
the block design for the KR260. No bitstream is distributed.

## Credits

| Material | Use in this variant | License / note |
| --- | --- | --- |
| [FreeRTOS Kernel](https://github.com/FreeRTOS/FreeRTOS-Kernel) V11.1.0, commit `dbf70559b27d39c1fdb68dfb9a32140b6a6777a0`, Copyright Amazon.com, Inc. or its affiliates | Real-time kernel of the firmware, included as a git submodule; files used unmodified | MIT License of the FreeRTOS Kernel (in the submodule). Not covered by the license of this repository. FreeRTOS is a trademark of Amazon Web Services, Inc. |
| [RISC-V ISA specifications](https://riscv.org/technical/specifications/), RISC-V International | Instruction set and privileged architecture implemented by the core | Specifications under CC BY 4.0. RISC-V is a registered trademark of RISC-V International. This core is an independent implementation; it is not certified by or affiliated with RISC-V International. |
| [lowRISC Ibex](https://github.com/lowRISC/ibex) | Design reference for trap entry, MRET, and CSR semantics; no source code included | Apache License 2.0 |
| [SERV](https://github.com/olofk/serv), Olof Kindgren | Design reference for CSR read/write semantics; no source code included | ISC License |
| [PicoRV32](https://github.com/YosysHQ/picorv32), Claire Xenia Wolf | Design reference for interrupt pending logic; no source code included | ISC License |
| H. Chamberlin, *Musical Applications of Microprocessors* | State-variable filter algorithm of `vrm_vcf_core` | Published algorithm; implementation is original |
| AMD Vivado IP (Zynq UltraScale+ MPSoC PS, AXI DMA, AXI GPIO, SmartConnect, Processor System Reset) | Instantiated by the block-design script; not included | Subject to the AMD/Xilinx license of the user's Vivado installation. Kria, Vivado, and Zynq are trademarks of AMD. |

All other files of this variant are original work under the MIT License of
this repository.
