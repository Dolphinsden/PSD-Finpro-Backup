/*******************************************************************************
 * File: sw/src/doomgeneric_zybo.c
 * Description: Bare-metal Zynq-7010 (ARM Cortex-A9) platform HAL for
 *              doomgeneric driving our custom pure-VHDL HDMI GPU core.
 *
 * Controls:
 *   1) Laptop Keyboard over Zybo onboard micro-USB UART (115200 8N1):
 *        W/A/S/D = Move/Turn, Z = Shoot, E/Space = Use/Open Door,
 *        Enter = Menu Select, Esc = Menu, 1-7 = Weapons, Q/R = Strafe
 *        (Run tools/doom_controller.py on laptop for smooth hold/release)
 *   2) Zybo Z7-10 Onboard Hardware (debounced in VHDL):
 *        BTN3 = A (Left), BTN2 = W (Forward), BTN1 = S (Back), BTN0 = D (Right)
 *        SW[0] = Shoot Toggle (UP = firing held, DOWN = release)
 *        SW[1] = Use / Menu Enter (toggle/flip to start game or open doors)
 *        SW[2] = Automap toggle
 *        SW[3] = Hardware HDMI SMPTE color-bar test mode
 ******************************************************************************/
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"
#include "xtime_l.h"

#include "doomgeneric.h"
#include "doomkeys.h"
#include "zybo_doom_hw.h"

/* Fallback UART base address for Zybo Z7-10 UART1 if macro name differs */
#ifndef STDIN_BASEADDRESS
#define STDIN_BASEADDRESS 0xE0001000U
#endif

/* Fallback Global Timer rate (Zybo Z7-10 CPU 666.667 MHz / 2 = 333.333 MHz) */
#ifndef COUNTS_PER_SECOND
#define COUNTS_PER_SECOND 333333333ULL
#endif

/*------------------------------------------------------------------------------
 * Key Event Ring Buffer (fed by both UART keyboard & Zybo hardware buttons/SW)
 *----------------------------------------------------------------------------*/
#define KEYQUEUE_SIZE 64

typedef struct {
    unsigned char key;
    int pressed;
} key_event_t;

static key_event_t s_key_queue[KEYQUEUE_SIZE];
static unsigned int s_kq_head = 0;
static unsigned int s_kq_tail = 0;

static uint32_t s_prev_hw_inputs = 0;
static uint8_t  s_uart_prefix    = 0;  /* '+' = press, '-' = release, 0 = none */
static uint64_t s_boot_ticks     = 0;

static void push_key_event(int pressed, unsigned char key)
{
    unsigned int next = (s_kq_head + 1U) % KEYQUEUE_SIZE;
    if (next == s_kq_tail) {
        return; /* Queue full */
    }
    s_key_queue[s_kq_head].key     = key;
    s_key_queue[s_kq_head].pressed = pressed ? 1 : 0;
    s_kq_head = next;
}

static unsigned char map_ascii_to_doom_key(unsigned char ch)
{
    if (ch >= 'A' && ch <= 'Z') {
        ch = (unsigned char)(ch - 'A' + 'a');
    }

    switch (ch) {
        case 'w': return KEY_UPARROW;
        case 's': return KEY_DOWNARROW;
        case 'a': return KEY_LEFTARROW;
        case 'd': return KEY_RIGHTARROW;
        case 'z': return KEY_FIRE;
        case 'e': return KEY_USE;
        case ' ': return KEY_USE;
        case 'n': return KEY_ENTER;
        case '\r':
        case '\n': return KEY_ENTER;
        case 'x': return KEY_ESCAPE;
        case 27:  return KEY_ESCAPE;
        case 'q': return KEY_STRAFE_L;
        case 'r': return KEY_STRAFE_R;
        case 'm': return KEY_TAB;
        case 'y': return 'y';
        case '1': case '2': case '3': case '4':
        case '5': case '6': case '7':
            return ch;
        default:
            return 0;
    }
}

/*------------------------------------------------------------------------------
 * Poll Zybo Hardware Buttons/Switches (from VHDL REG_INPUT) + USB-UART Keyboard
 *----------------------------------------------------------------------------*/
static void poll_all_inputs(void)
{
    /* 1. Hardware buttons & switches debounced inside zybo_doom_gpu_axi.vhd */
    uint32_t hw = Xil_In32(ZYBO_GPU_REG_INPUT) & 0xFFU;
    uint32_t diff = hw ^ s_prev_hw_inputs;

    if (diff != 0U) {
        if (diff & ZYBO_BTN2_W_MASK) {
            push_key_event((hw & ZYBO_BTN2_W_MASK) != 0U, KEY_UPARROW);
        }
        if (diff & ZYBO_BTN1_S_MASK) {
            push_key_event((hw & ZYBO_BTN1_S_MASK) != 0U, KEY_DOWNARROW);
        }
        if (diff & ZYBO_BTN3_A_MASK) {
            push_key_event((hw & ZYBO_BTN3_A_MASK) != 0U, KEY_LEFTARROW);
        }
        if (diff & ZYBO_BTN0_D_MASK) {
            push_key_event((hw & ZYBO_BTN0_D_MASK) != 0U, KEY_RIGHTARROW);
        }
        /* SW[0] acts as a shooting toggle: UP = hold fire, DOWN = release fire */
        if (diff & ZYBO_SW0_FIRE_MASK) {
            push_key_event((hw & ZYBO_SW0_FIRE_MASK) != 0U, KEY_FIRE);
        }
        /* SW[1] triggers Use / Menu Enter on rising edge so you can start/open doors */
        if (diff & ZYBO_SW1_USE_MASK) {
            int on = ((hw & ZYBO_SW1_USE_MASK) != 0U);
            push_key_event(on, KEY_USE);
            push_key_event(on, KEY_ENTER);
        }
        /* SW[2] toggles Automap */
        if (diff & ZYBO_SW2_MAP_MASK) {
            push_key_event(1, KEY_TAB);
            push_key_event(0, KEY_TAB);
        }
        s_prev_hw_inputs = hw;
    }

    /* 2. Laptop Keyboard over Zybo onboard USB-UART (non-blocking) */
    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        uint8_t b = (uint8_t)XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET);

        if (s_uart_prefix == '+' || s_uart_prefix == '-') {
            unsigned char dk = map_ascii_to_doom_key(b);
            if (dk != 0) {
                push_key_event(s_uart_prefix == '+', dk);
            }
            s_uart_prefix = 0;
        } else if (b == '+' || b == '-') {
            /* 2-byte press/release packet from tools/doom_controller.py */
            s_uart_prefix = b;
        } else {
            /* Raw single-character fallback if typing directly in a serial terminal */
            unsigned char dk = map_ascii_to_doom_key(b);
            if (dk != 0) {
                push_key_event(1, dk);
                push_key_event(0, dk);
            }
        }
    }
}

/*------------------------------------------------------------------------------
 * Custom VHDL GPU Palette & Framebuffer Upload Hooks
 *----------------------------------------------------------------------------*/
void zybo_update_palette(const uint8_t *rgb768)
{
    volatile uint32_t *pal_dst = (volatile uint32_t *)ZYBO_GPU_PAL_BASE;
    for (int i = 0; i < 256; i++) {
        uint32_t r = rgb768[i * 3 + 0];
        uint32_t g = rgb768[i * 3 + 1];
        uint32_t b = rgb768[i * 3 + 2];
        pal_dst[i] = (r << 16) | (g << 8) | b;
    }
}

void zybo_present_8bit(const uint8_t *fb_320x200)
{
    /* Wait briefly if a previous VSYNC swap hasn't completed yet (max ~16ms) */
    uint32_t guard = 0;
    while ((Xil_In32(ZYBO_GPU_REG_CTRL) & ZYBO_CTRL_SWAP_REQ) != 0U) {
        if (++guard > 2000000U) {
            break;
        }
    }

    /* Pack 4 indexed 8-bit pixels per 32-bit AXI write (16,000 words = 64 KB) */
    const uint32_t *src32 = (const uint32_t *)fb_320x200;
    volatile uint32_t *dst32 = (volatile uint32_t *)ZYBO_GPU_FB_BASE;
    for (int i = 0; i < (320 * 200) / 4; i++) {
        dst32[i] = src32[i];
    }

    /* Enable live DOOM display + request tear-free VSYNC page flip */
    Xil_Out32(ZYBO_GPU_REG_CTRL, ZYBO_CTRL_DISP_EN | ZYBO_CTRL_SWAP_REQ);
}

/*------------------------------------------------------------------------------
 * doomgeneric Platform API
 *----------------------------------------------------------------------------*/
void DG_Init(void)
{
    XTime now;
    XTime_GetTime(&now);
    s_boot_ticks = (uint64_t)now;

    uint32_t gpu_id = Xil_In32(ZYBO_GPU_REG_ID);
    uint32_t ctrl   = Xil_In32(ZYBO_GPU_REG_CTRL);

    xil_printf("\r\n============================================\r\n");
    xil_printf("  DOOM on Digilent Zybo Z7-10 (VHDL HDMI)\r\n");
    xil_printf("============================================\r\n");
    xil_printf("VHDL GPU ID   : 0x%08X (expected 0x%08X)\r\n",
               (unsigned int)gpu_id, (unsigned int)ZYBO_GPU_EXPECTED_ID);
    xil_printf("HDMI MMCM Lock: %s\r\n",
               (ctrl & ZYBO_CTRL_MMCM_LOCK) ? "LOCKED (640x480@60Hz)" : "UNLOCKED!");
    xil_printf("Controls      : Laptop WASD+Z via doom_controller.py\r\n");
    xil_printf("                Board BTN3=A BTN2=W BTN1=S BTN0=D SW0=FireToggle\r\n");

    /* Snapshot initial switch state so SW0=UP on boot immediately registers */
    s_prev_hw_inputs = 0;
    poll_all_inputs();
}

void DG_DrawFrame(void)
{
    /*
     * Note: Our patched i_video.c calls zybo_present_8bit(I_VideoBuffer) directly
     * so we avoid wasting ARM CPU cycles expanding 8-bit pixels to 32-bit RGB.
     * Just poll inputs here as well to keep latency minimal.
     */
    poll_all_inputs();
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t start = DG_GetTicksMs();
    while ((DG_GetTicksMs() - start) < ms) {
        poll_all_inputs();
    }
}

uint32_t DG_GetTicksMs(void)
{
    XTime now;
    XTime_GetTime(&now);
    uint64_t elapsed = (uint64_t)now - s_boot_ticks;
    return (uint32_t)((elapsed * 1000ULL) / (uint64_t)COUNTS_PER_SECOND);
}

int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    poll_all_inputs();

    if (s_kq_tail == s_kq_head) {
        return 0;
    }

    *pressed = s_key_queue[s_kq_tail].pressed;
    *doomKey = s_key_queue[s_kq_tail].key;
    s_kq_tail = (s_kq_tail + 1U) % KEYQUEUE_SIZE;
    return 1;
}

void DG_SetWindowTitle(const char *title)
{
    (void)title;
}

/*------------------------------------------------------------------------------
 * Bare-Metal Entry Point
 *----------------------------------------------------------------------------*/
int main(void)
{
    static char arg0[] = "doom";
    static char arg1[] = "-iwad";
    static char arg2[] = "DOOM1.WAD";
    static char *argv[] = { arg0, arg1, arg2, NULL };

    doomgeneric_Create(3, argv);

    while (1) {
        doomgeneric_Tick();
    }

    return 0;
}
