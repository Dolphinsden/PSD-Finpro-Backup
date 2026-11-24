#!/usr/bin/env python3
"""
File: scripts/setup_doom_sources.py
Description:
  Fetches ozkl/doomgeneric (GPL-2.0 DOOM C engine), copies only the portable
  bare-metal C sources into sw/app_src/, adds our Zybo Z7-10 HAL/WAD files,
  and applies 4 clean patches connecting DOOM to our custom VHDL HDMI GPU:
    1. doomgeneric.h -> native 320x200 resolution
    2. w_file.c      -> register mem_wad_file (embedded DDR3 DOOM1.WAD)
    3. m_misc.c      -> M_FileExists() recognizes embedded DOOM1.WAD
    4. i_video.c     -> stream 256-color palette & 8-bit 320x200 framebuffer
                        directly to our VHDL GPU registers (zybo_doom_gpu_axi)

Usage:
  python scripts/setup_doom_sources.py
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO_DIR = ROOT / "sw" / "doomgeneric_repo"
DG_SUBDIR = REPO_DIR / "doomgeneric"
APP_SRC = ROOT / "sw" / "app_src"
CUSTOM_SRC = ROOT / "sw" / "src"
WAD_FILE = ROOT / "sw" / "wad" / "DOOM1.WAD"

# Exclude OS-specific backends and audio/SDL backends (video-only bare-metal)
EXCLUDED_PREFIXES = (
    "doomgeneric_",
    "i_sdl",
    "i_allegro",
    "i_pcsound",
    "i_opl",
    "midifile",
    "mus2mid",
)
EXCLUDED_EXACT = {
    "icon.c",
}


def clone_doomgeneric():
    if DG_SUBDIR.is_dir():
        print(f"[OK] Found existing doomgeneric repo at {REPO_DIR}")
        return
    print("[1/4] Cloning https://github.com/ozkl/doomgeneric.git ...")
    subprocess.run(
        ["git", "clone", "--depth", "1", "https://github.com/ozkl/doomgeneric.git", str(REPO_DIR)],
        check=True,
    )


def copy_sources():
    print(f"[2/4] Assembling bare-metal C sources into {APP_SRC} ...")
    if APP_SRC.exists():
        shutil.rmtree(APP_SRC)
    APP_SRC.mkdir(parents=True, exist_ok=True)

    count = 0
    for item in sorted(DG_SUBDIR.iterdir()):
        if not item.is_file():
            continue
        if item.suffix.lower() not in (".c", ".h"):
            continue
        name_l = item.name.lower()
        if name_l in EXCLUDED_EXACT:
            continue
        if any(name_l.startswith(p) for p in EXCLUDED_PREFIXES):
            continue
        shutil.copy2(item, APP_SRC / item.name)
        count += 1

    # Copy our custom Zybo Z7-10 HAL, memory WAD loader, and .incbin assembly
    for item in sorted(CUSTOM_SRC.iterdir()):
        if item.is_file():
            shutil.copy2(item, APP_SRC / item.name)
            count += 1

    print(f"[OK] Copied {count} source/header files into sw/app_src/")


def patch_doomgeneric_h():
    p = APP_SRC / "doomgeneric.h"
    text = p.read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"#define\s+DOOMGENERIC_RESX\s+\d+", "#define DOOMGENERIC_RESX 320", text)
    text = re.sub(r"#define\s+DOOMGENERIC_RESY\s+\d+", "#define DOOMGENERIC_RESY 200", text)
    p.write_text(text, encoding="utf-8")
    print("[PATCH] doomgeneric.h -> 320x200 native resolution")


def patch_w_file_c():
    p = APP_SRC / "w_file.c"
    text = p.read_text(encoding="utf-8", errors="replace")
    if "mem_wad_file" in text:
        return

    text = text.replace(
        "extern wad_file_class_t stdc_wad_file;",
        "extern wad_file_class_t mem_wad_file;\nextern wad_file_class_t stdc_wad_file;",
        1,
    )
    text = text.replace(
        "&stdc_wad_file,",
        "&mem_wad_file,\n    &stdc_wad_file,",
        1,
    )
    p.write_text(text, encoding="utf-8")
    print("[PATCH] w_file.c -> registered mem_wad_file for embedded DDR3 DOOM1.WAD")


def patch_m_misc_c():
    p = APP_SRC / "m_misc.c"
    text = p.read_text(encoding="utf-8", errors="replace")
    if "zybo_is_embedded_wad" in text:
        return

    helper = (
        '\n#include <strings.h>\n'
        'static boolean zybo_is_embedded_wad(const char *path) {\n'
        '    if (!path) return false;\n'
        '    const char *s = strrchr(path, \'/\');\n'
        '    const char *b = strrchr(path, \'\\\\\');\n'
        '    const char *n = path;\n'
        '    if (s && s + 1 > n) n = s + 1;\n'
        '    if (b && b + 1 > n) n = b + 1;\n'
        '    return (strcasecmp(n, "doom1.wad") == 0) ? true : false;\n'
        '}\n'
    )
    # Inject helper before M_FileExists and fast-path DOOM1.WAD
    pattern = r"(boolean\s+M_FileExists\s*\(\s*char\s*\*\s*filename\s*\)\s*\{)"
    replacement = helper + r"\1\n    if (zybo_is_embedded_wad(filename)) return true;\n"
    new_text, n = re.subn(pattern, replacement, text, count=1)
    if n != 1:
        raise RuntimeError("Could not locate M_FileExists() in m_misc.c to patch.")
    p.write_text(new_text, encoding="utf-8")
    print("[PATCH] m_misc.c -> M_FileExists() recognizes embedded DOOM1.WAD")


def patch_i_video_c():
    p = APP_SRC / "i_video.c"
    text = p.read_text(encoding="utf-8", errors="replace")
    if "zybo_doom_hw.h" in text:
        return

    text = '#include "zybo_doom_hw.h"\n' + text

    # Hook I_SetPalette: forward gamma-corrected 256x3 palette to VHDL Palette LUT
    pal_hook = """
    /* Zybo Z7-10 VHDL Hardware Palette LUT upload */
    {
        uint8_t zybo_rgb[256 * 3];
        for (int z_i = 0; z_i < 256; z_i++) {
            zybo_rgb[z_i * 3 + 0] = gammatable[usegamma][palette[z_i * 3 + 0]];
            zybo_rgb[z_i * 3 + 1] = gammatable[usegamma][palette[z_i * 3 + 1]];
            zybo_rgb[z_i * 3 + 2] = gammatable[usegamma][palette[z_i * 3 + 2]];
        }
        zybo_update_palette(zybo_rgb);
    }
"""
    pal_pat = r"(void\s+I_SetPalette\s*\(\s*byte\s*\*\s*palette\s*\)\s*\{)"
    text, n1 = re.subn(pal_pat, r"\1" + pal_hook, text, count=1)
    if n1 != 1:
        raise RuntimeError("Could not locate I_SetPalette() in i_video.c to patch.")

    # Hook I_FinishUpdate: send native 320x200 8-bit I_VideoBuffer directly to VHDL BRAM
    fin_hook = """
    /* Zybo Z7-10 VHDL GPU direct 8-bit framebuffer present (skips 32-bit SW blit) */
    zybo_present_8bit(I_VideoBuffer);
    DG_DrawFrame();
    return;
"""
    fin_pat = r"(void\s+I_FinishUpdate\s*\(\s*void\s*\)\s*\{)"
    text, n2 = re.subn(fin_pat, r"\1" + fin_hook, text, count=1)
    if n2 != 1:
        raise RuntimeError("Could not locate I_FinishUpdate() in i_video.c to patch.")

    p.write_text(text, encoding="utf-8")
    print("[PATCH] i_video.c -> hooked I_SetPalette & I_FinishUpdate to VHDL GPU")


def check_wad():
    print("[4/4] Checking for DOOM1.WAD ...")
    WAD_FILE.parent.mkdir(parents=True, exist_ok=True)
    if WAD_FILE.is_file() and WAD_FILE.stat().st_size > 1_000_000:
        size_mb = WAD_FILE.stat().st_size / (1024 * 1024)
        print(f"[OK] Found {WAD_FILE} ({size_mb:.2f} MB)")
    else:
        print(
            "\n[ACTION REQUIRED] Missing shareware DOOM1.WAD!\n"
            f"  Please download shareware DOOM1.WAD (~4.2 MB) and save it to:\n"
            f"    {WAD_FILE}\n"
            "  before building in Vitis 2026.1.\n"
        )


def main():
    clone_doomgeneric()
    copy_sources()
    print("[3/4] Applying Zybo Z7-10 bare-metal patches ...")
    patch_doomgeneric_h()
    patch_w_file_c()
    patch_m_misc_c()
    patch_i_video_c()
    check_wad()
    print("\n=== DOOM C source setup complete! ===")


if __name__ == "__main__":
    main()
