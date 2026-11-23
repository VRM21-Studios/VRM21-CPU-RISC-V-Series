// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : port_vrm.c (gcc-firmware/rv32im_freertos)
// Description : SoC part of the FreeRTOS port: 1 kHz tick from the local timer
//               (MTIP, mcause 7), GPIO/VCF interrupt dispatch (MEIP, mcause 11),
//               and the fault handler that records a code at 0x1000_F01C.
// ============================================================================
#include "FreeRTOS.h"
#include "task.h"
#include "soc_map.h"

#define TIMER_ENABLE       1u
#define TIMER_AUTORELOAD   2u
#define TIMER_IRQ_ENABLE   4u
#define TIMER_PENDING      1u
#define FX_IRQ_MASK        0xfeu
#define DIAG ((volatile uint32_t *)0x1000f000u)

void vcf_gpio_irq(void);

void firmware_fault(unsigned code)
{
    DIAG[7] = code;
    portDISABLE_INTERRUPTS();
    for (;;) __asm__ volatile ("wfi");
}

void vPortSetupTimerInterrupt(void)
{
    TIMER_CTRL = 0;
    TIMER_STATUS = TIMER_PENDING;
    TIMER_COUNTER = 0;
    TIMER_COMPARE = configCPU_CLOCK_HZ / configTICK_RATE_HZ - 1;
    IRQ_CLEAR = FX_IRQ_MASK;
    IRQ_ENABLE = FX_IRQ_MASK;
    __asm__ volatile ("csrw mie, %0" :: "r"(MIE_MTIE | MIE_MEIE) : "memory");
    TIMER_CTRL = TIMER_ENABLE | TIMER_AUTORELOAD | TIMER_IRQ_ENABLE;
}

void freertos_risc_v_application_interrupt_handler(uint32_t cause)
{
    if (cause == 0x80000007u) {
        TIMER_STATUS = TIMER_PENDING;
        ++DIAG[1];
        portYIELD_FROM_ISR(xTaskIncrementTick());
    } else if (cause == 0x8000000bu) {
        vcf_gpio_irq();
    } else {
        firmware_fault(cause);
    }
}

void freertos_risc_v_application_exception_handler(uint32_t cause)
{
    firmware_fault(0x100u | cause);
}
