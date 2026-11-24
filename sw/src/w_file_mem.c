/*******************************************************************************
 * File: sw/src/w_file_mem.c
 * Description: Pluggable doomgeneric WAD reader serving DOOM1.WAD directly
 *              from embedded DDR3 memory (via doom1_wad.S .incbin).
 *              Eliminates SD card / FAT32 dependencies in bare-metal Vitis.
 ******************************************************************************/
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "w_file.h"
#include "z_zone.h"

extern const unsigned char _binary_doom1_wad_start[];
extern const unsigned char _binary_doom1_wad_end[];

typedef struct {
    wad_file_t wad;
    const unsigned char *base;
    unsigned int size;
} mem_wad_file_t;

extern wad_file_class_t mem_wad_file;

static int is_doom1_wad_name(const char *path)
{
    const char *slash = strrchr(path, '/');
    const char *bslash = strrchr(path, '\\');
    const char *name = path;

    if (slash && slash + 1 > name) {
        name = slash + 1;
    }
    if (bslash && bslash + 1 > name) {
        name = bslash + 1;
    }
    return (strcasecmp(name, "doom1.wad") == 0);
}

static wad_file_t *W_Mem_OpenFile(char *path)
{
    if (!is_doom1_wad_name(path)) {
        return NULL;
    }

    unsigned int wad_len = (unsigned int)(_binary_doom1_wad_end - _binary_doom1_wad_start);
    if (wad_len < 12U) {
        return NULL;
    }

    mem_wad_file_t *result = Z_Malloc(sizeof(mem_wad_file_t), PU_STATIC, 0);
    result->wad.file_class = &mem_wad_file;
    result->wad.mapped     = (byte *)_binary_doom1_wad_start;
    result->wad.length     = wad_len;
    result->base           = _binary_doom1_wad_start;
    result->size           = wad_len;

    return &result->wad;
}

static void W_Mem_CloseFile(wad_file_t *wad)
{
    mem_wad_file_t *mwad = (mem_wad_file_t *)wad;
    Z_Free(mwad);
}

static size_t W_Mem_Read(wad_file_t *wad, unsigned int offset,
                         void *buffer, size_t buffer_len)
{
    mem_wad_file_t *mwad = (mem_wad_file_t *)wad;
    if (offset >= mwad->size) {
        return 0;
    }
    size_t avail = mwad->size - offset;
    size_t to_copy = (buffer_len < avail) ? buffer_len : avail;
    memcpy(buffer, mwad->base + offset, to_copy);
    return to_copy;
}

wad_file_class_t mem_wad_file = {
    W_Mem_OpenFile,
    W_Mem_CloseFile,
    W_Mem_Read,
};
