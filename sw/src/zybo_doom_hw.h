/*******************************************************************************
 * File: sw/src/zybo_doom_hw.h
 * Description: Hardware register definitions for the custom pure-VHDL
 *              zybo_doom_gpu_axi peripheral mapped at 0x43C0_0000.
 ******************************************************************************/
#ifndef ZYBO_DOOM_HW_H
#define ZYBO_DOOM_HW_H

#include <stdint.h>

#define ZYBO_GPU_BASEADDR   0x43C00000U

/* 64 KB back-buffer write window (320x200 x 8-bit = 16,000 x 32-bit words) */
#define ZYBO_GPU_FB_BASE    (ZYBO_GPU_BASEADDR + 0x00000U)

/* 256-entry 24-bit RGB Hardware Palette LUT (write 0x00RRGGBB) */
#define ZYBO_GPU_PAL_BASE   (ZYBO_GPU_BASEADDR + 0x10000U)

/* Control & Status Registers */
#define ZYBO_GPU_REG_CTRL   (ZYBO_GPU_BASEADDR + 0x10400U)
#define ZYBO_GPU_REG_INPUT  (ZYBO_GPU_BASEADDR + 0x10404U)
#define ZYBO_GPU_REG_LED    (ZYBO_GPU_BASEADDR + 0x10408U)
#define ZYBO_GPU_REG_FCNT   (ZYBO_GPU_BASEADDR + 0x1040CU)
#define ZYBO_GPU_REG_ID     (ZYBO_GPU_BASEADDR + 0x10410U)

#define ZYBO_GPU_EXPECTED_ID 0xD0000001U

/* REG_CTRL bits */
#define ZYBO_CTRL_SWAP_REQ   (1U << 0)
#define ZYBO_CTRL_DISP_EN    (1U << 1)
#define ZYBO_CTRL_MMCM_LOCK  (1U << 2)
#define ZYBO_CTRL_VSYNC      (1U << 3)
#define ZYBO_CTRL_ACTIVE_BUF (1U << 4)

/* REG_INPUT bit masks (debounced in VHDL) */
#define ZYBO_BTN0_D_MASK     (1U << 0)  /* BTN0 = D (Turn Right) */
#define ZYBO_BTN1_S_MASK     (1U << 1)  /* BTN1 = S (Move Backward) */
#define ZYBO_BTN2_W_MASK     (1U << 2)  /* BTN2 = W (Move Forward) */
#define ZYBO_BTN3_A_MASK     (1U << 3)  /* BTN3 = A (Turn Left) */
#define ZYBO_SW0_FIRE_MASK   (1U << 4)  /* SW0  = Fire Toggle */
#define ZYBO_SW1_USE_MASK    (1U << 5)  /* SW1  = Use / Enter */
#define ZYBO_SW2_MAP_MASK    (1U << 6)  /* SW2  = Automap Toggle */
#define ZYBO_SW3_TEST_MASK   (1U << 7)  /* SW3  = Hardware HDMI Color Bars */

/* Hooks called by patched doomgeneric/i_video.c */
void zybo_update_palette(const uint8_t *rgb768);
void zybo_present_8bit(const uint8_t *fb_320x200);

#endif /* ZYBO_DOOM_HW_H */
