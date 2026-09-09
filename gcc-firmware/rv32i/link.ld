/*
 * ============================================================================
 * VRM RV32I SoC LINKER SCRIPT
 * ============================================================================
 *
 * This linker script defines the memory layout of firmware executed by the
 * VRM RV32I SoC.
 *
 * The firmware image is linked to the beginning of the unified 64-KB system
 * RAM. During system startup, the hardware bootloader copies the firmware
 * image into this memory region before releasing the CPU.
 *
 * Memory Organization:
 *
 *   Base Address : 0x00000000
 *   Size         : 64 KB
 *
 * The memory region contains:
 *
 *   - Startup and interrupt vectors
 *   - Executable code
 *   - Read-only data
 *   - Initialized data
 *   - Uninitialized data
 *   - Runtime stack
 * ============================================================================
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)


/*
 * ============================================================================
 * MEMORY REGIONS
 * ============================================================================
 */

MEMORY
{
    /*
     * Unified system RAM.
     *
     * The firmware is loaded into this region by the hardware bootloader.
     */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00010000
}


/*
 * ============================================================================
 * SECTION LAYOUT
 * ============================================================================
 */

SECTIONS
{
    /*
     * ------------------------------------------------------------------------
     * CODE AND READ-ONLY DATA
     * ------------------------------------------------------------------------
     *
     * The .init section is placed first to ensure that the reset and interrupt
     * vectors occupy the lowest addresses in the firmware image.
     *
     * Expected vector layout:
     *
     *   0x00000000 : Reset vector
     *   0x00000004 : Interrupt vector
     */

    .text :
    {
        /*
         * Startup code and processor vectors.
         */
        KEEP(*(.init))

        /*
         * Executable program code.
         */
        *(.text*)

        /*
         * Read-only program data.
         */
        *(.rodata*)

        /*
         * Maintain 32-bit alignment for subsequent sections.
         */
        . = ALIGN(4);

    } > RAM


    /*
     * ------------------------------------------------------------------------
     * INITIALIZED DATA
     * ------------------------------------------------------------------------
     *
     * Contains global and static variables with initial values.
     */

    .data :
    {
        . = ALIGN(4);

        *(.data*)

        . = ALIGN(4);

    } > RAM


    /*
     * ------------------------------------------------------------------------
     * UNINITIALIZED DATA
     * ------------------------------------------------------------------------
     *
     * Contains global and static variables without explicit initialization.
     *
     * The NOLOAD attribute prevents this section from unnecessarily increasing
     * the firmware image size.
     */

    .bss (NOLOAD) :
    {
        . = ALIGN(4);

        __bss_start = .;

        *(.bss*)
        *(COMMON)

        . = ALIGN(4);

        __bss_end = .;

    } > RAM


    /*
     * ------------------------------------------------------------------------
     * STACK
     * ------------------------------------------------------------------------
     *
     * The stack grows downward from the top of the unified system RAM.
     */

    PROVIDE(_stack_top = ORIGIN(RAM) + LENGTH(RAM));


    /*
     * ------------------------------------------------------------------------
     * FIRMWARE IMAGE BOUNDARY
     * ------------------------------------------------------------------------
     *
     * Marks the end of the linked firmware image and can be used by build
     * tools or future bootloader implementations.
     */

    PROVIDE(_firmware_end = .);
}
