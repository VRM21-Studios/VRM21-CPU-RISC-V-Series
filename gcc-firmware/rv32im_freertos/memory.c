// ============================================================================
// VRM21 Studios - VRM21-CPU-RISC-V-Series
//
// File        : memory.c (gcc-firmware/rv32im_freertos)
// Description : Freestanding memcpy and memset for the -nostdlib build.
// ============================================================================
#include <string.h>

void *memcpy(void *restrict dst, const void *restrict src, size_t size)
{
    unsigned char *out = dst;
    const unsigned char *in = src;
    for (size_t i = 0; i < size; ++i)
        out[i] = in[i];
    return dst;
}

void *memset(void *dst, int value, size_t size)
{
    unsigned char *out = dst;
    for (size_t i = 0; i < size; ++i)
        out[i] = (unsigned char)value;
    return dst;
}
