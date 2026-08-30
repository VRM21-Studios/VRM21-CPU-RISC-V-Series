OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY {
  /*
   * Unified 16 KB RAM mapped from address 0x4000 to 0x8000.
   */
  RAM (rwx) : ORIGIN = 0x00004000, LENGTH = 0x4000
}

SECTIONS {
  /*
   * Program code and read-only constants.
   */
  .text : {
    *(.init)
    *(.text*)
    *(.rodata*)
  } > RAM

  /*
   * Initialized data and zero-initialized data.
   */
  .data : { *(.data*) } > RAM
  .bss  : { *(.bss*)  } > RAM

  /*
   * Place the stack pointer at the top of the available RAM.
   * RAM end address = 0x4000 + 0x4000 = 0x8000.
   */
  PROVIDE( _stack_top = ORIGIN(RAM) + LENGTH(RAM) );
}
