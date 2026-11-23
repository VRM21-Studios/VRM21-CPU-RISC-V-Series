// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : FreeRTOSConfig.h (gcc-firmware/rv32im_freertos)
// Description : FreeRTOS kernel configuration: 100 MHz CPU clock, 1 kHz tick,
//               static allocation only, no MTIME (the SoC timer drives MTIP).
// ============================================================================
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H
#define configCPU_CLOCK_HZ                      100000000UL
#define configTICK_RATE_HZ                      1000U
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION  0
#define configMAX_PRIORITIES                    4
#define configMINIMAL_STACK_SIZE                128U
#define configMAX_TASK_NAME_LEN                 4
#define configTICK_TYPE_WIDTH_IN_BITS           TICK_TYPE_WIDTH_32_BITS
#define configUSE_IDLE_HOOK                     1
#define configUSE_TICK_HOOK                     0
#define configSUPPORT_DYNAMIC_ALLOCATION        0
#define configSUPPORT_STATIC_ALLOCATION         1
#define configKERNEL_PROVIDED_STATIC_MEMORY     0
#define configUSE_TIMERS                        0
#define configUSE_MUTEXES                       0
#define configUSE_TASK_NOTIFICATIONS            0
#define configUSE_CO_ROUTINES                   0
#define configMTIME_BASE_ADDRESS                0
#define configMTIMECMP_BASE_ADDRESS             0
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_vTaskSuspend                    1
void firmware_fault(unsigned code) __attribute__((noreturn));
#define configASSERT(condition) do { if (!(condition)) firmware_fault(1); } while (0)
#endif
