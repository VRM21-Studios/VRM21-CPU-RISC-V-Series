# Build: rv32im_freertos Firmware

The firmware is built with the `Makefile` in this folder. It needs the
FreeRTOS kernel submodule, GNU Make, Python 3, and a bare-metal RISC-V GCC 12
or newer (the published image was built with GCC 14.2.0).

```bash
# from the repository root
git submodule update --init gcc-firmware/rv32im_freertos/FreeRTOS-Kernel

cd gcc-firmware/rv32im_freertos
make                                  # outputs in this folder
# make OUT=build                      # outputs in ./build
# make CROSS=riscv32-unknown-elf-     # other toolchain prefix
```

Compiler flags:

```text
-march=rv32im_zicsr -mabi=ilp32 -Oz -flto -ffreestanding -fno-builtin
-fno-delete-null-pointer-checks -ffunction-sections -fdata-sections
-msmall-data-limit=0 -mno-relax
link: -nostdlib -T link.ld -Wl,--gc-sections,--no-relax
```

Outputs:

| File | Content |
| --- | --- |
| `firmware.elf` | linked image, entry `0x1000_1000` |
| `firmware.bin` | raw image loaded at `0x1000_1000` |
| `firmware.mem` | bootloader image, byte tokens, offsets relative to `0x1000_1000` |
| `firmware.map` | linker map |
| `boot_wait.mem` | WFI seed for the legacy boot mode |

After the build, `scripts/rv32im_freertos/check_boot_image.py` verifies that
the ELF, BIN, and MEM describe the same image of at most 16 KiB.

To use a new image in simulation and synthesis, copy it to the include
folder:

```bash
cp firmware.mem ../../include/rv32im_freertos/firmware.mem
```

The generated files in this folder are not tracked by Git.
