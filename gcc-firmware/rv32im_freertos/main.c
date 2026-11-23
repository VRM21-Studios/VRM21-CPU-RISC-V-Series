// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : main.c (gcc-firmware/rv32im_freertos)
// Description : FreeRTOS application for the RV32IM + VCF SoC.
//               - Three static tasks: TX (producer), RX (consumer), REG
//                 (register/context probe with DIV/REM), plus the idle task.
//               - GPIO interrupt (arbiter bits 1..7) applies VCF presets:
//                 bit 1 = CLEAR (bypass), bits 2..7 = FX 1..6.
//               - Diagnostic block at 0x1000_F000, read by the testbench and
//                 the host: [0] marker 0x46525431, [1] tick, [2] TX, [3] RX,
//                 [4] semaphore/probe, [5] idle, [6] preemption, [7] fault.
// Build       : see build_script.md in this folder.
// ============================================================================
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "soc_map.h"

#define DIAG ((volatile uint32_t *)0x1000f000u)
#define STACK_WORDS 160u

typedef struct {
    uint32_t cutoff_q15;
    uint32_t res_q15;
    uint32_t lco;
    uint32_t ftype;
} vcf_preset_t;

#define FX_NUM_PRESETS      6u

static const vcf_preset_t FX_PRESETS[FX_NUM_PRESETS] = {
    /* FX 1 lowpass_default */ { 0x2666u, 0x0CCCu, 15u, VCF_FTYPE_LP },
    /* FX 2 highpass        */ { 0x1999u, 0x0CCCu, 15u, VCF_FTYPE_HP },
    /* FX 3 bandpass        */ { 0x2000u, 0x2666u, 15u, VCF_FTYPE_BP },
    /* FX 4 resonant_lp     */ { 0x3333u, 0x6666u, 20u, VCF_FTYPE_LP },
    /* FX 5 bright_hp       */ { 0x1333u, 0x4000u, 18u, VCF_FTYPE_HP },
    /* FX 6 vocal_bp        */ { 0x1999u, 0x4CCCu, 18u, VCF_FTYPE_BP },
};

// Shadow values restored by CLEAR and at boot (= FX 1, lowpass_default)
#define FX_BOOT_PRESET      (&FX_PRESETS[0])

// ============================================================================
// IRQ_PENDING BIT DEFINITIONS
// ============================================================================
//   Bit 0     : timer via arbiter    (NOT used — timer uses MTIP direct)
//   Bit 1..7  : ext_irq_in[0..6]     (FX CLEAR, FX 1..6)
//   Bit 8-31  : free for future use
#define IRQ_PEND_FX_SHIFT   1u
#define IRQ_PEND_FX_CLEAR   (1u << IRQ_PEND_FX_SHIFT)
#define IRQ_PEND_FX_MASK    (((1u << (FX_NUM_PRESETS + 1u)) - 1u) << IRQ_PEND_FX_SHIFT)  // 0xFE

static void vcf_load_shadows(const vcf_preset_t *p)
{
    // Shadow writes only; each of them also cancels a pending commit.
    // The CTRL write that follows arms the commit.
    VCF_CUTOFF = p->cutoff_q15;
    VCF_RES    = p->res_q15;
    VCF_LCO    = p->lco;
}

// FX 1..6: load shadows, then enable + ftype + commit in one CTRL write.
// The CTRL write is the last write, so all four values are applied together
// at the first zero crossing after it (or after the ZCD timeout).
static void vcf_apply_preset(const vcf_preset_t *p)
{
    vcf_load_shadows(p);
    VCF_CTRL = VCF_CTRL_WORD(1, p->ftype, 1);
}

// FX CLEAR (and boot): bypass, shadows back to the boot preset.
// enable = 0 -> zero-latency passthrough. CTRL is written with commit = 0,
// so any pending commit is cancelled; the active parameters stay as they
// are until the next FX (or host write) arms a new commit.
static void vcf_clear(void)
{
    vcf_load_shadows(FX_BOOT_PRESET);
    VCF_CTRL = VCF_CTRL_OFF_LP;
}

void vcf_gpio_irq(void)
{
    uint32_t pending = IRQ_PENDING;

    // Nothing latched in the arbiter (spurious entry): ignore.
    if (pending == 0) return;

    uint32_t fx = (pending & IRQ_PEND_FX_MASK) >> IRQ_PEND_FX_SHIFT;

    if (fx & 1u) {
        // FX CLEAR has priority over any preset latched at the same time
        vcf_clear();
    } else {
        for (uint32_t k = 1u; k <= FX_NUM_PRESETS; k++) {
            if (fx & (1u << k)) {
                vcf_apply_preset(&FX_PRESETS[k - 1u]);
                break;
            }
        }
    }

    // Clear every latched FX bit (write 1 to clear)
    IRQ_CLEAR = pending & IRQ_PEND_FX_MASK;
}

static StaticTask_t task_tcb[3];
static StackType_t task_stack[3][STACK_WORDS] __attribute__((aligned(16)));
static StaticQueue_t queue_state, semaphore_state;
static uint32_t queue_item;
static QueueHandle_t queue;
static SemaphoreHandle_t semaphore;
static volatile uint32_t worker_active;
static volatile uint32_t boot_data = 0x13579bdfu;
static volatile uint32_t boot_bss;
extern unsigned context_probe(volatile uint32_t *tick, uint32_t until);

void vApplicationGetIdleTaskMemory(StaticTask_t **tcb, StackType_t **stack,
                                   configSTACK_DEPTH_TYPE *depth)
{
    static StaticTask_t idle_tcb;
    static StackType_t idle_stack[configMINIMAL_STACK_SIZE] __attribute__((aligned(16)));
    *tcb = &idle_tcb;
    *stack = idle_stack;
    *depth = configMINIMAL_STACK_SIZE;
}

void vApplicationIdleHook(void)
{
    ++DIAG[5];
    __asm__ volatile ("wfi");
}

static void producer(void *arg)
{
    (void)arg;
    uint32_t sequence = 0;
    for (;;) {
        vTaskDelay(5);
        if (worker_active)
            ++DIAG[6];
        vTaskDelay(5);
        ++sequence;
        if (xQueueSend(queue, &sequence, 0) != pdPASS)
            firmware_fault(3);
        ++DIAG[2];
    }
}

static void consumer(void *arg)
{
    (void)arg;
    uint32_t previous = 0, received;
    for (;;) {
        if (xQueueReceive(queue, &received, portMAX_DELAY) != pdPASS ||
            received != previous + 1)
            firmware_fault(4);
        previous = received;
        ++DIAG[3];
        if (xSemaphoreGive(semaphore) != pdPASS)
            firmware_fault(5);
    }
}

static void worker(void *arg)
{
    (void)arg;
    for (;;) {
        if (xSemaphoreTake(semaphore, portMAX_DELAY) != pdPASS)
            firmware_fault(6);
        worker_active = 1;
        if (context_probe(&DIAG[1], DIAG[1] + 6) != 0)
            firmware_fault(7);
        worker_active = 0;
        ++DIAG[4];
        vTaskDelay(1);
    }
}

int main(void)
{
    for (unsigned i = 0; i < 8; ++i)
        DIAG[i] = 0;
    if (boot_data != 0x13579bdfu || boot_bss != 0)
        firmware_fault(9);
    boot_data = 0;
    boot_bss = 0x2468ace0u;
    DIAG[0] = 0x46525431u;
    vcf_clear();
    queue = xQueueCreateStatic(1, sizeof(queue_item), (uint8_t *)&queue_item, &queue_state);
    semaphore = xSemaphoreCreateBinaryStatic(&semaphore_state);
    (void)xTaskCreateStatic(producer, "TX", STACK_WORDS, 0, 2, task_stack[0], &task_tcb[0]);
    (void)xTaskCreateStatic(consumer, "RX", STACK_WORDS, 0, 3, task_stack[1], &task_tcb[1]);
    (void)xTaskCreateStatic(worker, "REG", STACK_WORDS, 0, 1, task_stack[2], &task_tcb[2]);
    vTaskStartScheduler();
    firmware_fault(8);
}
