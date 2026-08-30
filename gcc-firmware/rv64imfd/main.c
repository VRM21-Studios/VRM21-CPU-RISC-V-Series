#include "soc_map.h"

/*
 * Signal completion to the testbench through the RISC-V breakpoint instruction.
 */
#define SIGNAL_DONE() asm volatile ("ebreak")

/*
 * Minimal machine-mode timer interrupt handler.
 *
 * This handler is intentionally kept simple so that the firmware
 * remains compatible with the current bare-metal testbench environment.
 */
void __attribute__((interrupt("machine"))) timer_isr(void) {
    TIMER_STATUS = 0;
}

/*
 * Initialize the VRM CPU pipeline and disable system timer interrupts.
 *
 * static inline + always_inline keeps the initialization sequence
 * self-contained and prevents unnecessary stack usage.
 */
static inline __attribute__((always_inline)) void init_vrm_cpu_pipeline() {
    TIMER_CTRL = 0;
    IRQ_ENABLE = 0;
    IRQ_CLEAR = 0xFFFFFFFF;
}

/*
 * Busy-wait for a fixed number of CPU cycles.
 *
 * The register qualifier and always_inline attribute are used to
 * keep the delay loop lightweight for the bare-metal testbench.
 */
static inline __attribute__((always_inline)) void delay_cycles(register int cycles) {
    while(cycles--) {
        asm volatile ("nop");
    }
}

/*
 * Main testbench firmware entry point.
 *
 * The function intentionally never returns.
 */
void __attribute__((noreturn)) main() {
    init_vrm_cpu_pipeline();

    OSC_TARGET_PHASE_INC = 42949673;
    OSC_AMP_MAX          = 131071;
    OSC_LFO_PHASE_INC    = 42949673;
    OSC_RESET_RUN        = 1;
    OSC_PACKET_SIZE      = 64;
    OSC_GLIDE_ALPHA      = 1000;
    OSC_SNAP_TO_TARGET   = 0;

    register int wait_time = 1500;

    /*
     * Synthesizer functional sweep.
     *
     * This sequence is currently intended as a placeholder / testbench
     * stimulus for the planned VRM Synthesizer Series.
     */

    // Test oscillator mode across all available wavetable banks.
    OSC_GEN_MODE    = 0;
    OSC_WAVE_SELECT = 0;
    delay_cycles(wait_time);

    OSC_WAVE_SELECT = 1;
    delay_cycles(wait_time);

    OSC_WAVE_SELECT = 2;
    delay_cycles(wait_time);

    OSC_WAVE_SELECT = 3;
    delay_cycles(wait_time);

    // Test sub-oscillator mode.
    OSC_GEN_MODE = 1;
    delay_cycles(wait_time);

    // Test LFO mode across the available waveform types.
    OSC_GEN_MODE      = 2;
    OSC_LFO_WAVE_TYPE = 0;
    delay_cycles(wait_time);

    OSC_LFO_WAVE_TYPE = 1;
    delay_cycles(wait_time);

    OSC_LFO_WAVE_TYPE = 2;
    delay_cycles(wait_time);

    // Test noise generator mode.
    OSC_GEN_MODE = 3;
    delay_cycles(wait_time);

    /*
     * Notify the testbench that the firmware sequence has completed.
     */
    SIGNAL_DONE();

    /*
     * Keep the processor in a deterministic idle loop after completion.
     */
    while(1) {
        asm volatile ("nop");
    }
}
