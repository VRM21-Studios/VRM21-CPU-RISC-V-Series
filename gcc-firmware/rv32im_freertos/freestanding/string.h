// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : freestanding/string.h
// Description : Declarations of the freestanding memcpy and memset (memory.c).
// ============================================================================
#ifndef RV32_FREESTANDING_STRING_H
#define RV32_FREESTANDING_STRING_H
#include <stddef.h>
void *memcpy(void *restrict dst, const void *restrict src, size_t size);
void *memset(void *dst, int value, size_t size);
#endif
