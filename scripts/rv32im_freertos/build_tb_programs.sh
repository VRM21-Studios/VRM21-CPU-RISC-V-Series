#!/usr/bin/env bash
# ============================================================================
# VRM21 Studios - VRM21-CPU-RISC-V-Series
#
# Script  : scripts/rv32im_freertos/build_tb_programs.sh
# Purpose : Assemble the directed test programs of tb_rv32im_regression and
#           write their bootloader images to tb/rv32im_freertos/mem/<test>.mem.
# Run     : bash scripts/rv32im_freertos/build_tb_programs.sh
#           CROSS=riscv32-unknown-elf- MARCH=rv32im bash ...   (overrides)
# Toolchain: a bare-metal RISC-V GCC. GCC 12 or newer needs MARCH=rv32im_zicsr
#           (default); GCC 11 and older accept only MARCH=rv32im.
# Layout  : sources in tb/rv32im_freertos/programs/*.S; wfi_timer_masked is
#           wfi_timer.S built with -DMASKED.
# ============================================================================
set -eu
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
src=$repo/tb/rv32im_freertos/programs
out=$repo/tb/rv32im_freertos/mem
CROSS=${CROSS:-riscv64-unknown-elf-}
MARCH=${MARCH:-rv32im_zicsr}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$out"

for test_name in wfi_store byte_enable wfi_timer wfi_timer_masked; do
    program=$test_name
    flags=()
    if [[ "$test_name" == wfi_timer_masked ]]; then
        program=wfi_timer
        flags=(-DMASKED)
    fi
    "${CROSS}gcc" -march="$MARCH" -mabi=ilp32 -nostdlib -Wl,-Ttext=0,--no-relax \
        ${flags[@]+"${flags[@]}"} "$src/$program.S" -o "$work/$test_name.elf"
    "${CROSS}objcopy" -O verilog "$work/$test_name.elf" "$out/$test_name.mem"
    echo "built $out/$test_name.mem"
done
