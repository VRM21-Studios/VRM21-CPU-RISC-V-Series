#!/bin/bash

# ============================================================================
# VRM RV32I Firmware Build Script
# ============================================================================

set -e

echo "=============================================="
echo "       VRM RV32I Firmware Build"
echo "=============================================="

# Move to the firmware source directory.
cd /path/to/files


# ============================================================================
# 1. COMPILE AND LINK
# ============================================================================
#
# Target ISA:
#   RV32I
#
# ABI:
#   ILP32
#
# The firmware is built as a freestanding bare-metal application without
# the standard C runtime or host operating-system support.
# ============================================================================

echo "[1/3] Compiling and linking firmware..."

riscv64-unknown-elf-gcc \
    -march=rv32i \
    -mabi=ilp32 \
    -O2 \
    -ffreestanding \
    -fno-builtin \
    -nostdlib \
    -T link.ld \
    boot.S \
    main.c \
    -o firmware.elf


# ============================================================================
# 2. GENERATE VERILOG MEMORY IMAGE
# ============================================================================
#
# The Verilog-format memory image can be loaded into a Verilog/SystemVerilog
# instruction-memory model or converted for use with a Vivado simulation flow.
# ============================================================================

echo "[2/3] Generating Verilog memory image..."

riscv64-unknown-elf-objcopy \
    -O verilog \
    firmware.elf \
    firmware.mem


# ============================================================================
# 3. GENERATE DISASSEMBLY
# ============================================================================
#
# The disassembly is useful for verifying instruction encoding, addresses,
# control-flow targets, MMIO accesses, and debugging CPU simulation results.
# ============================================================================

echo "[3/3] Generating disassembly..."

riscv64-unknown-elf-objdump \
    -D \
    firmware.elf \
    > firmware.dump


# ============================================================================
# BUILD SUMMARY
# ============================================================================

echo ""
echo "=============================================="
echo "             Build completed"
echo "=============================================="
echo "Output files:"
echo "  firmware.elf  - Linked ELF firmware image"
echo "  firmware.mem  - Verilog memory initialization image"
echo "  firmware.dump - Disassembled firmware"
echo "=============================================="
