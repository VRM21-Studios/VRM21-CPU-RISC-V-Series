#include "soc_map.h"

// ============================================================================
// MACHINE-MODE TIMER INTERRUPT SERVICE ROUTINE
// ============================================================================
//
// The compiler's machine-mode interrupt calling convention is requested
// through the interrupt attribute.
//
// The timer interrupt is acknowledged by clearing TIMER_STATUS. After the
// interrupt service routine returns, program execution continues normally.
// ============================================================================

void __attribute__((interrupt("machine"))) timer_isr(void)
{
// Clear the timer interrupt-pending flag.
TIMER_STATUS = 0;
}

// ============================================================================
// CPU / SYSTEM INITIALIZATION
// ============================================================================
//
// Initialize the basic system state before entering the main firmware loop.
//
// The timer and all interrupt sources are disabled initially. Pending interrupt
// sources are cleared to provide a deterministic startup state.
// ============================================================================

void init_vrm_system(void)
{
// Disable the hardware timer.
TIMER_CTRL = 0;


// Disable all interrupt sources in the interrupt arbiter.
IRQ_ENABLE = 0;

// Clear all pending interrupt sources.
IRQ_CLEAR = 0xFFFFFFFFUL;


}

// ============================================================================
// APPLICATION ENTRY POINT
// ============================================================================
//
// The hardware bootloader transfers this firmware image into system memory
// before releasing the CPU.
//
// After system initialization, the processor enters the WFI state and remains
// available for interrupt-driven operation.
// ============================================================================

int main(void)
{
// Initialize the CPU-side system and peripheral state.
init_vrm_system();


// Main interrupt-driven execution loop.
while (1)
{
    // Enter the low-activity wait state until an interrupt occurs.
    asm volatile ("wfi");
}

return 0;


}
