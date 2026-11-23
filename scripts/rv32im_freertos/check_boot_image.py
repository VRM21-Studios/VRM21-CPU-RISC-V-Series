"""Check the RV32 payload and its byte-addressed bootloader MEM.

VRM21 Studios - VRM21-CPU-RISC-V-Series

Purpose : verify that firmware.elf, firmware.bin, and firmware.mem describe
          the same autoboot image: entry 0x1000_1000, word-aligned size of at
          most 16 KiB, ELF load segments equal to the BIN, and the MEM byte
          image equal to the BIN.
Run     : python3 check_boot_image.py firmware.elf firmware.bin firmware.mem
          (called by gcc-firmware/rv32im_freertos/Makefile after each build)
Exit    : 0 and one summary line when valid; otherwise exits with a message.
"""
import argparse
import struct
from pathlib import Path

IMAGE_BASE = 0x10001000
IMAGE_CAPACITY = 16 * 1024


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def read_mem(path):
    result = bytearray()
    for line in path.read_text().splitlines():
        for token in line.partition("//")[0].split():
            if token.startswith("@"):
                require(int(token[1:], 16) == len(result), "Invalid MEM byte offset")
            else:
                require(len(token) == 2, "MEM must contain byte tokens")
                require(len(result) < IMAGE_CAPACITY, "MEM exceeds 16 KiB")
                result.append(int(token, 16))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("binary", type=Path)
    parser.add_argument("mem", type=Path)
    args = parser.parse_args()

    elf = args.elf.read_bytes()
    payload = args.binary.read_bytes()
    require(0 < len(payload) <= IMAGE_CAPACITY and len(payload) % 4 == 0,
            "BIN must be nonempty, word aligned and fit in 16 KiB")
    require(elf[:7] == b"\x7fELF\x01\x01\x01" and len(elf) >= 52,
            "Expected ELF32 little-endian")
    _, machine, _, entry, phoff = struct.unpack_from("<HHIII", elf, 16)
    phsize, phcount = struct.unpack_from("<HH", elf, 42)
    require(machine == 243 and entry == IMAGE_BASE,
            "RISC-V ELF entry must equal autoboot RAM base 0x10001000")
    require(phsize == 32 and phoff + phcount * phsize <= len(elf),
            "Invalid ELF program header table")

    image = bytearray(len(payload))
    loaded_end = 0
    for index in range(phcount):
        segment = struct.unpack_from("<8I", elf, phoff + index * phsize)
        kind, offset, _, address, file_size, _, flags, _ = segment
        if kind != 1 or file_size == 0:
            continue
        start = address - IMAGE_BASE
        end = start + file_size
        require(start >= loaded_end and end <= len(payload) and offset + file_size <= len(elf),
                "Invalid or overlapping ELF load segment for autoboot")
        if start == 0:
            require(flags & 1, "Autoboot must start in an executable ELF segment")
        image[start:end] = elf[offset:offset + file_size]
        loaded_end = end

    require(loaded_end == len(payload) and image == payload,
            "ELF load segments do not match BIN")
    require(read_mem(args.mem) == payload, "MEM byte image does not match BIN")
    print(f"Autoboot image valid: {len(payload)} bytes, base 0x{IMAGE_BASE:08x}, "
          f"last byte 0x{IMAGE_BASE + len(payload) - 1:08x}, capacity {IMAGE_CAPACITY} bytes")


if __name__ == "__main__":
    main()
