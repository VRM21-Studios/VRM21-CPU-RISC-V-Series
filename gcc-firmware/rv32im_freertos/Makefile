# ============================================================================
# VRM21 Studios - VRM21-CPU-RISC-V-Series
#
# Makefile for gcc-firmware/rv32im_freertos
# Builds the FreeRTOS autoboot image for the RV32IM + VCF SoC and checks it.
#
# Usage (from this folder, after "git submodule update --init"):
#   make                      # outputs in this folder
#   make OUT=build            # outputs in ./build
#   make CROSS=riscv32-unknown-elf-
# Outputs: firmware.elf, firmware.bin, firmware.mem (byte image, offsets
# relative to 0x1000_1000), firmware.map, boot_wait.mem.
# Copy firmware.mem to include/rv32im_freertos/ to update the RTL boot image.
# ============================================================================
CROSS ?= riscv64-unknown-elf-
CC := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
SIZE := $(CROSS)size
KERNEL := FreeRTOS-Kernel
PORT := $(KERNEL)/portable/GCC/RISC-V
OUT ?= .
PYTHON ?= python3
FLAGS := -march=rv32im_zicsr -mabi=ilp32 -Oz -flto -ffreestanding -fno-builtin \
         -fno-delete-null-pointer-checks -ffunction-sections -fdata-sections \
         -msmall-data-limit=0 -mno-relax
INCLUDES := -I. -Ifreestanding -I$(KERNEL)/include -I$(PORT) \
            -I$(PORT)/chip_specific_extensions/RISCV_no_extensions
SOURCES := boot.S context_probe.S main.c memory.c port_vrm.c \
           $(KERNEL)/tasks.c $(KERNEL)/list.c $(KERNEL)/queue.c $(PORT)/port.c $(PORT)/portASM.S
HEADERS := $(wildcard *.h freestanding/*.h $(KERNEL)/include/*.h $(PORT)/*.h \
           $(PORT)/chip_specific_extensions/RISCV_no_extensions/*.h)

.PHONY: all
all: $(OUT)/firmware.elf $(OUT)/firmware.bin $(OUT)/firmware.mem $(OUT)/firmware.map $(OUT)/boot_wait.mem
	$(PYTHON) ../../scripts/rv32im_freertos/check_boot_image.py $(OUT)/firmware.elf $(OUT)/firmware.bin $(OUT)/firmware.mem
	$(SIZE) $(OUT)/firmware.elf
	wc -c $(OUT)/firmware.bin

$(OUT)/firmware.elf $(OUT)/firmware.map &: $(SOURCES) $(HEADERS) link.ld Makefile
	mkdir -p $(OUT)
	$(CC) $(FLAGS) $(INCLUDES) -nostdlib -T link.ld \
		-Wl,--gc-sections,--no-relax,-Map=$(OUT)/firmware.map $(SOURCES) -o $(OUT)/firmware.elf

$(OUT)/firmware.bin: $(OUT)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(OUT)/firmware.mem: $(OUT)/firmware.elf
	$(OBJCOPY) -O verilog --change-addresses=-0x10001000 $< $@

$(OUT)/boot_wait.elf: boot_wait.S Makefile
	mkdir -p $(OUT)
	$(CC) -march=rv32im_zicsr -mabi=ilp32 -nostdlib -Wl,-Ttext=0,--no-relax $< -o $@

$(OUT)/boot_wait.mem: $(OUT)/boot_wait.elf
	$(OBJCOPY) -O verilog $< $@
