# DOOM on Digilent Zybo Z7-10 (Pure-VHDL HDMI GPU + Bare-Metal ARM DOOM)

Runs original **1993 DOOM** over **HDMI (640×480 @ 60 Hz)** on a **Digilent Zybo Z7-10** using:
- **FPGA Fabric (100% Pure VHDL + XDC — zero third-party IP, zero AXI VDMA, zero Verilog):** Custom AXI4-Lite GPU core (`zybo_doom_gpu_axi.vhd`) with a double-buffered 320×200×8-bit BRAM framebuffer, 256-color hardware Palette LUT, 2× pixel scaler, debounced hardware button/switch register, SMPTE test screen, and custom DVI/HDMI TMDS TX (`OSERDESE2` + `OBUFDS`).
- **Zynq-7010 ARM Cortex-A9 (C — strictly for DOOM):** Bare-metal `doomgeneric` port running out of the board's 1 GB DDR3 RAM with shareware `DOOM1.WAD` embedded directly into DDR3 (zero microSD card needed).

---

## 1. What You Need to Prepare

### Hardware
1. **Digilent Zybo Z7-10** board (`XC7Z010-1CLG400C`)
   - Set **JP5 (Boot Mode)** to **JTAG** (middle/JTAG position).
   - Set **JP6 (Power Select)** to **USB** (unless using a 5V wall adapter).
2. **Micro-USB cable** (data-capable, not charge-only) connected from your Windows laptop to the Zybo **PROG / UART** port (`J12`).
3. **HDMI cable** + **HDMI monitor** connected to the Zybo **HDMI TX** port (`J11`, the port closer to the Ethernet jack on Z7-10).

### Software (Windows)
1. **AMD Vivado 2026.1 + AMD Vitis 2026.1** (both included in the AMD Unified Installer — make sure **Vitis** is checked, not just Vivado, because Vitis compiles the ARM C code for DOOM).
2. **Git** and **Python 3** (with `pyserial`: run `pip install pyserial`).
3. **Shareware `DOOM1.WAD`** (~4.2 MB, freely redistributable id Software shareware v1.9) saved to:
   `sw/wad/DOOM1.WAD`
4. *(Optional)* Digilent Zybo Z7-10 Vivado board files — **not required**, because `scripts/create_project.tcl` automatically applies the exact Zybo Z7-10 DDR3/UART1 preset if board files are not installed.

---

## 2. Project Structure

```text
zybo_z7_10_doom_vhdl/
├── src/                        # 100% Pure VHDL FPGA Hardware
│   ├── clock_gen_hdmi.vhd      # MMCME2_BASE: 125 MHz -> 25.208 MHz pix + 126.042 MHz 5x TMDS
│   ├── input_debouncer.vhd     # 2-FF sync + 12 ms debouncer for BTN[3:0] & SW[3:0]
│   ├── vga_timing_gen.vhd      # Standard VESA 640x480 @ 60 Hz timing + VBLANK pulse
│   ├── tmds_encoder.vhd        # Full DVI 1.0 8b/10b TMDS encoder with DC balance
│   ├── hdmi_tx_phy.vhd         # 4-lane 10:1 DDR OSERDESE2 cascade + OBUFDS (TMDS_33)
│   └── zybo_doom_gpu_axi.vhd   # AXI4-Lite GPU: 128 KB double-buffered BRAM, 256-color LUT, 2x scaler
├── constraints/
│   └── zybo_z7_10_doom.xdc     # Verified Zybo Z7-10 pins (K17 clk, HDMI TX, BTN/SW/LED)
├── sim/
│   └── tb_zybo_doom_gpu.vhd    # Self-checking pure-VHDL simulation testbench
├── sw/
│   ├── src/
│   │   ├── zybo_doom_hw.h      # VHDL GPU AXI register map (0x43C0_0000)
│   │   ├── doomgeneric_zybo.c  # Bare-metal ARM HAL (VHDL GPU + UART + board buttons/SW0)
│   │   ├── w_file_mem.c        # In-memory WAD file driver (reads DDR3 directly)
│   │   ├── doom1_wad.S         # Embeds DOOM1.WAD via .incbin into DDR3
│   │   └── syscalls_zybo.c     # Minimal bare-metal POSIX stubs
│   └── wad/
│       └── DOOM1.WAD           # <-- Place your downloaded shareware DOOM1.WAD here
├── scripts/
│   ├── create_project.tcl      # Vivado 2026.1 project + Block Design + VHDL wrapper builder
│   ├── build_bitstream.tcl     # Headless Vivado Synth -> Impl -> .bit + .xsa export
│   ├── setup_doom_sources.py   # Clones ozkl/doomgeneric & applies Zybo bare-metal patches
│   ├── build_vitis.py          # Vitis 2026.1 CLI builder -> build/zybo_doom.elf
│   └── run_doom_jtag.tcl       # One-command XSDB JTAG bitstream + DOOM launcher
└── tools/
    └── doom_controller.py      # Windows laptop WASD + Z keyboard bridge over USB-UART
```

---

## 3. Step-by-Step Build & Run Guide (Vivado & Vitis 2026.1)

Open a **Vivado/Vitis 2026.1 Command Prompt** (or PowerShell after running `settings64.bat`) inside this project folder.

### Step 1 — Build the FPGA Bitstream & XSA in Vivado 2026.1
```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```
*(Or open Vivado 2026.1 GUI -> **Tools -> Run Tcl Script** -> `scripts/create_project.tcl`, inspect the Block Design & VHDL, click **Generate Bitstream**, then **File -> Export -> Export Hardware (Include bitstream)** to `build/zybo_doom.xsa`.)*

Outputs:
- `build/zybo_doom.bit`
- `build/zybo_doom.xsa`

**Quick HDMI Sanity Test (before Vitis):**
Program `build/zybo_doom.bit` onto the Zybo Z7-10 via Vivado Hardware Manager. Your HDMI monitor will immediately lock at **640×480 @ 60 Hz** and display the built-in VHDL **8-bar SMPTE color test pattern with a moving white bar** (`LED[0]` = ON means HDMI MMCM locked).

### Step 2 — Prepare DOOM C Sources & `DOOM1.WAD`
1. Download shareware **`DOOM1.WAD`** (~4.2 MB) and save it to `sw/wad/DOOM1.WAD`.
2. Run the setup script to fetch `ozkl/doomgeneric` and apply the Zybo VHDL GPU patches:
```powershell
python scripts/setup_doom_sources.py
```

### Step 3 — Build Bare-Metal DOOM in Vitis 2026.1
```powershell
vitis -s scripts/build_vitis.py
```
Output:
- `build/zybo_doom.elf` (includes embedded `DOOM1.WAD` in DDR3)

### Step 4 — Program & Launch DOOM on the Zybo Z7-10
Plug in the HDMI cable + micro-USB cable, turn the Zybo power switch **ON**, and run:
```powershell
xsdb scripts/run_doom_jtag.tcl
```
DOOM will immediately boot onto your HDMI monitor!

### Step 5 — Play with Laptop Keyboard (`WASD + Z`) AND/OR Zybo Buttons
```powershell
pip install pyserial
python tools/doom_controller.py
```

---

## 4. Controls Reference

### Laptop Keyboard (via `tools/doom_controller.py` over USB-UART)
| Key | Action |
| :--- | :--- |
| `W` / `S` | Move Forward / Backward |
| `A` / `D` | Turn Left / Turn Right |
| `Z` | Shoot (Fire) |
| `E` or `Space` | Use / Open Door |
| `Enter` / `Esc` | Menu Select / Pause Menu |
| `Q` / `R` | Strafe Left / Strafe Right |
| `1` – `7` | Select Weapon |
| `M` | Toggle Automap |

### Zybo Z7-10 Onboard Hardware (Debounced in VHDL)
| Control | Zybo Pin | Action |
| :--- | :--- | :--- |
| `BTN3` (far left) | `Y16` | `A` — Turn Left |
| `BTN2` (mid-left) | `K19` | `W` — Move Forward |
| `BTN1` (mid-right) | `P16` | `S` — Move Backward |
| `BTN0` (far right) | `K18` | `D` — Turn Right |
| `SW[0]` | `G15` | **Shoot Toggle** (UP = continuous fire, DOWN = stop) |
| `SW[1]` | `P15` | Use / Open Door & Menu Enter |
| `SW[2]` | `W13` | Toggle Automap |
| `SW[3]` | `T16` | **Hardware HDMI Color-Bar Test Mode** (overrides DOOM screen) |

### Zybo Status LEDs
| LED | Meaning |
| :--- | :--- |
| `LED[0]` | HDMI MMCM Clock Locked (solid ON = 25.208 MHz / 126.042 MHz active) |
| `LED[1]` | DOOM Live Framebuffer Enabled by ARM |
| `LED[2]` | `SW[0]` Fire Toggle Active |
| `LED[3]` | 60 Hz VSYNC Heartbeat (~1 Hz blink) |

---

## 5. VHDL Simulation (Optional Verification)
In Vivado 2026.1 after running `scripts/create_project.tcl`, click **Flow Navigator -> Simulation -> Run Behavioral Simulation**. `sim/tb_zybo_doom_gpu.vhd` automatically verifies:
- AXI4-Lite GPU ID read (`0xD0000001`)
- 256-color Palette LUT and back-buffer BRAM writes
- VSYNC swap & display enable
- MMCM lock (`LED[0] = '1'`) and differential HDMI TMDS clock activity

---

## 6. Resource Footprint on Zybo Z7-10 (`XC7Z010`)
- **BRAM:** ~33 / 60 BRAM36 tiles (~55% — 32 tiles for double-buffered 128 KB framebuffer + 1 tile for 256×24-bit Palette LUT)
- **LUTs:** ~1,200 / 17,600 (< 7%)
- **MMCM:** 1 / 2 (`MMCME2_BASE`)
- **OSERDESE2:** 8 (4 master/slave 10:1 DDR pairs for HDMI R, G, B, CLK)
