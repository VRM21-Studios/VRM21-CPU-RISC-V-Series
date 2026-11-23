/* VRM21 Studios - VRM21-CPU-RISC-V-Series
 * link.ld (gcc-firmware/rv32im_freertos): image at 0x1000_1000 (autoboot slot),
 * .data/.bss at 0x1000_6000, stacks up to 0x1001_0000, diagnostics at 0x1000_F000.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    IMAGE (rx) : ORIGIN = 0x10001000, LENGTH = 20K
    RAM (rw) : ORIGIN = 0x10006000, LENGTH = 36K
}
SECTIONS {
    .text : {
        KEEP(*(.init))
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > IMAGE
    .data : {
        __data_start = .;
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT > IMAGE
    __data_load = LOADADDR(.data);
    .bss (NOLOAD) : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM
    __image_bytes = LOADADDR(.data) + SIZEOF(.data) - ORIGIN(IMAGE);
    _stack_top = 0x10010000;
    __freertos_irq_stack_top = _stack_top;
    /DISCARD/ : { *(.eh_frame*) *(.note.gnu.build-id) }
    ASSERT(__bss_end <= 0x1000f000, "RAM overlaps diagnostics/stack")
}
