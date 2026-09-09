#include "soc_map.h"


// ============================================================================
// DEBUG / SIMULATION CONTROL
// ============================================================================
//
// EBREAK is used as a software breakpoint for simulation and debugging.
//
// The instruction itself does not replace the hardware WFI mechanism.
// Its behavior depends on the exception/debug handling implemented by the
// processor and the surrounding test environment.
// ============================================================================

#define SIGNAL_DONE() \
    asm volatile ("ebreak")


/* ============================================================================
 * MACHINE-MODE TIMER INTERRUPT SERVICE ROUTINE
 * ============================================================================
 *
 * The compiler's machine-mode interrupt calling convention is requested
 * through the interrupt attribute.
 *
 * The timer interrupt is acknowledged by clearing TIMER_STATUS.
 * ========================================================================== */

void __attribute__((interrupt("machine"))) timer_isr(void)
{
    // Clear the timer interrupt-pending flag.
    TIMER_STATUS = 0;
}


/* ============================================================================
 * CPU / SYSTEM INITIALIZATION
 * ============================================================================
 *
 * Disable system-generated interrupts before starting the main application.
 * This provides a deterministic initial state for firmware-level tests.
 * ========================================================================== */

void init_vrm_cpu_pipeline(void)
{
    // Disable the hardware timer.
    TIMER_CTRL = 0;

    // Disable all interrupt sources in the interrupt arbiter.
    IRQ_ENABLE = 0;

    // Clear all pending interrupt sources.
    IRQ_CLEAR = 0xFFFFFFFFUL;

    // Signal that system initialization has completed.
    SIGNAL_DONE();
}


/* ============================================================================
 * APPLICATION ENTRY POINT
 * ============================================================================
 */

int main(void)
{
    // Initialize the CPU-side system and peripheral state.
    init_vrm_cpu_pipeline();

    // Signal completion of firmware initialization to the simulation/debug
    // environment.
    SIGNAL_DONE();

    // Keep the processor alive if the application returns unexpectedly.
    while (1)
    {
        asm volatile ("nop");
    }

    return 0;
}
