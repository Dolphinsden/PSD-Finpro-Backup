/*------------------------------------------------------------------------------
 * File: sw/src/doom1_wad.S
 * Description: Embeds shareware DOOM1.WAD (~4.2 MB) directly into .rodata
 *              in the Zybo Z7-10's 1 GB DDR3 RAM at link time.
 *              Place your downloaded DOOM1.WAD in sw/wad/DOOM1.WAD before build.
 *              Assembler flag required: -Wa,-I<project_root>/sw/wad
 *----------------------------------------------------------------------------*/
    .section .rodata.doom1_wad, "a"
    .balign 4
    .global _binary_doom1_wad_start
    .global _binary_doom1_wad_end

_binary_doom1_wad_start:
    .incbin "DOOM1.WAD"
_binary_doom1_wad_end:
