.section .init
.global _start

_start:
    j reset_handler          # Reset vector at address 0x00

isr_vector:                  # Interrupt vector at address 0x04
    j timer_isr              # Jump to the C ISR handler

reset_handler:
    la sp, _stack_top
    jal ra, main             # Enter the main() function

halt:
    wfi
    j halt                   # Fallback loop if main() unexpectedly returns
