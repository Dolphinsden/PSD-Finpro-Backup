#!/usr/bin/env python3
"""
File: scripts/build_vitis.py
Description:
  AMD Vitis Unified IDE 2026.1 Python automation script.
  Creates the Zybo Z7-10 Standalone platform from build/zybo_doom.xsa,
  creates the bare-metal DOOM application component from sw/app_src/,
  configures a 32 MB DDR3 heap + embedded DOOM1.WAD include path, and
  builds build/zybo_doom.elf.

Usage (from Vitis 2026.1 Command Prompt / PowerShell):
  vitis -s scripts/build_vitis.py
"""
import os
import shutil
import sys
from pathlib import Path

import vitis

ROOT = Path(__file__).resolve().parent.parent
WS_DIR = ROOT / "vitis_ws"
XSA_FILE = ROOT / "build" / "zybo_doom.xsa"
APP_SRC = ROOT / "sw" / "app_src"
WAD_DIR = ROOT / "sw" / "wad"
WAD_FILE = WAD_DIR / "DOOM1.WAD"
OUT_ELF = ROOT / "build" / "zybo_doom.elf"


def main():
    if not XSA_FILE.is_file():
        sys.exit(
            f"ERROR: Missing {XSA_FILE}.\n"
            "Run Vivado first: vivado -mode batch -source scripts/build_bitstream.tcl"
        )
    if not APP_SRC.is_dir() or not (APP_SRC / "doomgeneric_zybo.c").is_file():
        sys.exit(
            f"ERROR: Missing prepared DOOM sources in {APP_SRC}.\n"
            "Run first: python scripts/setup_doom_sources.py"
        )
    if not WAD_FILE.is_file():
        sys.exit(
            f"ERROR: Missing {WAD_FILE}.\n"
            "Download shareware DOOM1.WAD (~4.2 MB) and save it to sw/wad/DOOM1.WAD"
        )

    if WS_DIR.exists():
        shutil.rmtree(WS_DIR)
    WS_DIR.mkdir(parents=True, exist_ok=True)

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WS_DIR))

        print("=== [1/4] Creating Standalone Platform from zybo_doom.xsa ===")
        platform = client.create_platform_component(
            name="zybo_doom_plat",
            hw_design=str(XSA_FILE),
            os="standalone",
            cpu="ps7_cortexa9_0",
            domain_name="standalone_ps7_cortexa9_0",
        )
        platform.build()

        xpfm = WS_DIR / "zybo_doom_plat" / "export" / "zybo_doom_plat" / "zybo_doom_plat.xpfm"

        print("=== [2/4] Creating Bare-Metal DOOM Application Component ===")
        app = client.create_app_component(
            name="zybo_doom_app",
            platform=str(xpfm),
            domain="standalone_ps7_cortexa9_0",
            template="empty_application",
        )

        # Import all prepared DOOM C/H/S files
        app.import_files(from_loc=str(APP_SRC), dest_dir_in_cmp="src")

        # Configure C compiler flags (-O2, bare-metal) & assembler WAD include path
        wad_inc = str(WAD_DIR).replace("\\", "/")
        app.set_app_config(
            key="USER_COMPILE_OPTIMIZATION_LEVEL",
            values="-O2",
        )
        app.set_app_config(
            key="USER_COMPILE_OTHER_FLAGS",
            values=f"-Wno-unused-variable -Wno-unused-function -Wa,-I{wad_inc}",
        )

        # Increase linker heap & stack in lscript.ld for DOOM (32 MB heap, 256 KB stack)
        lscript = WS_DIR / "zybo_doom_app" / "src" / "lscript.ld"
        if lscript.is_file():
            ld_text = lscript.read_text(encoding="utf-8", errors="replace")
            ld_text = ld_text.replace("_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x2000;",
                                      "_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x2000000;")
            ld_text = ld_text.replace("_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x2000;",
                                      "_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x40000;")
            lscript.write_text(ld_text, encoding="utf-8")
            print("[OK] Updated lscript.ld -> 32 MB DDR3 heap, 256 KB stack")

        print("=== [3/4] Compiling DOOM ELF (with embedded DOOM1.WAD) ===")
        app.build()

        built_elf = WS_DIR / "zybo_doom_app" / "build" / "zybo_doom_app.elf"
        if not built_elf.is_file():
            sys.exit(f"ERROR: Build finished but {built_elf} not found.")

        shutil.copy2(built_elf, OUT_ELF)
        print(f"=== [4/4] Success! ELF written to: {OUT_ELF} ===")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
