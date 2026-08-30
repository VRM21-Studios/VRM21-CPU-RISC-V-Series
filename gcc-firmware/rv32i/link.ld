OUTPUT_ARCH("riscv")
ENTRY(_start)

# ============================================================================
# VRM RV32I MEMORY LAYOUT
#
# The initial firmware image is linked into the 4 KB system RAM region.
#
# RAM:
#   Base address : 0x00000000
#   Size         : 4 KB
#
# The hardware timer and interrupt arbiter are mapped outside this RAM region:
#   Timer          : 0x00001000
#   IRQ Arbiter    : 0x00002000
# ============================================================================

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x1000
}


# ============================================================================
# SECTION LAYOUT
# ============================================================================

SECTIONS
{
    # ------------------------------------------------------------------------
    # Program code and read-only data
    # ------------------------------------------------------------------------
    .text :
    {
        . = ALIGN(4);

        *(.init)
        *(.text*)
        *(.rodata*)

        . = ALIGN(4);
    } > RAM


    # ------------------------------------------------------------------------
    # Initialized global/static data
    # ------------------------------------------------------------------------
    .data :
    {
        . = ALIGN(4);

        *(.data*)

        . = ALIGN(4);
    } > RAM


    # ------------------------------------------------------------------------
    # Zero-initialized global/static data
    # ------------------------------------------------------------------------
    .bss :
    {
        . = ALIGN(4);

        *(.bss*)
        *(COMMON)

        . = ALIGN(4);
    } > RAM


    # ------------------------------------------------------------------------
    # Stack
    #
    # The stack grows downward from the top of the available RAM region.
    # ------------------------------------------------------------------------
    PROVIDE(_stack_top = ORIGIN(RAM) + LENGTH(RAM));
}
