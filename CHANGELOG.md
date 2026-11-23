# Changelog

All notable changes to this repository are recorded here. Versions follow
Semantic Versioning once a release is tagged.

## [Unreleased]

### Added

- `rv32im_freertos` variant: RV32IM core with machine-mode traps (illegal
  instruction, ECALL, EBREAK), RV32M multiply/divide unit, byte-enable stores,
  WFI wake with and without the global interrupt enable, 64 KiB unified RAM,
  stereo state-variable filter (VCF) with atomic zero-crossing commit, and a
  hardware bootloader that starts FreeRTOS automatically.
  - RTL: `rtl/rv32im_freertos/`, `include/rv32im_freertos/`
  - Testbenches and XSim runner: `tb/rv32im_freertos/`,
    `scripts/rv32im_freertos/run_sim.ps1`
  - FreeRTOS V11.1.0 firmware: `gcc-firmware/rv32im_freertos/` with the
    FreeRTOS Kernel as a git submodule
  - Kria KR260 block-design script: `scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl`
  - Documentation: `docs/rv32im_freertos/`
- Validation status of the variant: FPGA-validated on the Kria KR260
  (100 MHz, WNS +0.644 ns); see `docs/rv32im_freertos/06_validation.md`.
- Credits section in the README for RISC-V, FreeRTOS, design references, and
  AMD IP.
- `.gitignore`: build folder, local settings, firmware build outputs.

### Unchanged

- The `rv32i` variant (RTL, testbenches, firmware, documentation).
