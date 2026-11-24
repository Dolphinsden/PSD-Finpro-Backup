/*******************************************************************************
 * File: sw/src/syscalls_zybo.c
 * Description: Minimal bare-metal POSIX stubs so doomgeneric links cleanly
 *              against Vitis newlib without an SD card filesystem.
 ******************************************************************************/
#include <errno.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

static int is_embedded_wad(const char *path)
{
    if (!path) {
        return 0;
    }
    const char *slash = strrchr(path, '/');
    const char *bslash = strrchr(path, '\\');
    const char *name = path;
    if (slash && slash + 1 > name) name = slash + 1;
    if (bslash && bslash + 1 > name) name = bslash + 1;
    return (strcasecmp(name, "doom1.wad") == 0);
}

__attribute__((weak)) int mkdir(const char *path, mode_t mode)
{
    (void)path;
    (void)mode;
    errno = ENOSYS;
    return -1;
}

__attribute__((weak)) int remove(const char *path)
{
    (void)path;
    errno = ENOSYS;
    return -1;
}

__attribute__((weak)) int rename(const char *oldpath, const char *newpath)
{
    (void)oldpath;
    (void)newpath;
    errno = ENOSYS;
    return -1;
}

__attribute__((weak)) int access(const char *path, int mode)
{
    (void)mode;
    if (is_embedded_wad(path)) {
        return 0;
    }
    errno = ENOENT;
    return -1;
}
