.section .init

.global _start
.global reset_handler


/*
 * ============================================================================
 * RESET VECTOR
 * ============================================================================
 *
 * The VRM RV32I CPU begins execution at address 0x00000000.
 *
 * The reset vector transfers control to reset_handler, which performs the
 * minimal processor initialization required before entering the C runtime.
 * ============================================================================
 */

_start:
    j reset_handler


/*
 * ============================================================================
 * INTERRUPT VECTOR
 * ============================================================================
 *
 * The CPU redirects machine-mode interrupts to address 0x00000004.
 *
 * This vector transfers control to the timer interrupt service routine.
 *
 * Additional interrupt dispatch logic can be added here if the SoC supports
 * multiple interrupt sources or software-based interrupt identification.
 * ============================================================================
 */

isr_vector:
    j timer_isr


/*
 * ============================================================================
 * RESET HANDLER
 * ============================================================================
 *
 * The reset handler performs the minimum initialization required before the
 * main C firmware is executed.
 *
 * Initialization sequence:
 *
 *   1. Initialize the stack pointer.
 *   2. Transfer control to main().
 *
 * The firmware is loaded into system RAM by the hardware bootloader before
 * the CPU is released from reset.
 * ============================================================================
 */

reset_handler:

    /*
     * Initialize the stack pointer using the address provided by the linker.
     */
    la sp, _stack_top

    /*
     * Enter the main C firmware.
     */
    jal ra, main


/*
 * ============================================================================
 * FALLBACK HALT HANDLER
 * ============================================================================
 *
 * main() is expected to remain active for the lifetime of the firmware.
 *
 * If main() unexpectedly returns, the processor enters the WFI state rather
 * than continuing execution into undefined memory.
 *
 * The processor remains capable of responding to a valid interrupt.
 * ============================================================================
 */

halt:
    wfi
    j halt
