.section .init
.global _start

# ============================================================================
# VRM RV32I CPU - Boot and Interrupt Vector
#
# Memory layout:
#   0x00000000 : Reset vector
#   0x00000004 : Machine-mode interrupt vector
#
# The reset vector transfers execution to reset_handler.
# The interrupt vector transfers execution to timer_isr.
# ============================================================================

_start:
    # Reset vector
    # Jump to the main reset handler.
    j reset_handler


# ============================================================================
# MACHINE INTERRUPT VECTOR
# ============================================================================

isr_vector:
    # Transfer control to the timer interrupt service routine.
    # The ISR is compiled using the machine-mode interrupt calling convention.
    j timer_isr


# ============================================================================
# RESET HANDLER
# ============================================================================

reset_handler:
    # Initialize the stack pointer using the linker-provided stack symbol.
    la sp, _stack_top

    # Enter the C runtime/application entry point.
    jal ra, main


# ============================================================================
# FALLBACK HALT LOOP
# ============================================================================

halt:
    # Keep the processor idle if main() ever returns.
    wfi

    # Resume execution here if WFI returns without a handled interrupt.
    j halt
