#!/usr/bin/env python3
"""
File: tools/doom_controller.py
Description:
  Windows laptop keyboard-to-Zybo-Z7-10 USB-UART bridge for DOOM.
  Reads real-time key press/release states via Windows user32.GetAsyncKeyState
  (no admin rights, no pynput needed — only pyserial) and sends 2-byte '+k'/'-k'
  packets over the Zybo's onboard micro-USB serial port @ 115200 baud.

Controls:
  W / A / S / D   : Move Forward / Turn Left / Move Backward / Turn Right
  Z               : Shoot (Fire)
  E or Space      : Use / Open Door
  Enter           : Menu Select
  Esc             : Menu / Pause
  Q / R           : Strafe Left / Strafe Right
  1 - 7           : Select Weapon
  M               : Automap
  Y               : Confirm (Yes)
  Ctrl+C          : Quit controller

Install dependency once:
  pip install pyserial

Usage:
  python tools/doom_controller.py            (auto-detects Zybo COM port)
  python tools/doom_controller.py COM5       (explicit COM port)
"""
import ctypes
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.exit("Missing pyserial. Install it with: pip install pyserial")

if sys.platform != "win32":
    sys.exit("This script uses Windows GetAsyncKeyState. Run it on Windows.")

GetAsyncKeyState = ctypes.windll.user32.GetAsyncKeyState

# Virtual-Key Code -> protocol character understood by doomgeneric_zybo.c
KEY_MAP = {
    ord("W"): "w",
    ord("A"): "a",
    ord("S"): "s",
    ord("D"): "d",
    ord("Z"): "z",
    ord("E"): "e",
    0x20: " ",      # Space (Use / Open door)
    0x0D: "n",      # Enter (Menu select)
    0x1B: "x",      # Escape (Menu)
    ord("Q"): "q",  # Strafe left
    ord("R"): "r",  # Strafe right
    ord("M"): "m",  # Automap
    ord("Y"): "y",  # Yes
    ord("1"): "1",
    ord("2"): "2",
    ord("3"): "3",
    ord("4"): "4",
    ord("5"): "5",
    ord("6"): "6",
    ord("7"): "7",
}


def find_zybo_port() -> str:
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        sys.exit("No COM ports found. Plug in your Zybo Z7-10 micro-USB cable and power it on.")

    # Prefer Digilent / FTDI USB Serial Port
    for p in ports:
        desc = f"{p.description} {p.manufacturer or ''}".lower()
        if "ftdi" in desc or "digilent" in desc or "usb serial" in desc:
            return p.device

    print("Available COM ports:")
    for p in ports:
        print(f"  {p.device}: {p.description}")
    return ports[0].device


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else find_zybo_port()
    print(f"Connecting to Zybo Z7-10 UART on {port} @ 115200 baud...")

    ser = serial.Serial(port=port, baudrate=115200, timeout=0)
    print(
        "\n=== DOOM Laptop Controller Active ===\n"
        "  WASD        : Move / Turn\n"
        "  Z           : Shoot\n"
        "  E / Space   : Open Door / Use\n"
        "  Enter / Esc : Menu Confirm / Back\n"
        "  1-7         : Weapons   |  Q/R : Strafe\n"
        "  Ctrl+C      : Exit controller\n"
        "-------------------------------------\n"
    )

    pressed_state = {vk: False for vk in KEY_MAP}

    try:
        while True:
            # Print any debug/boot output coming from the Zybo Z7-10
            incoming = ser.read(256)
            if incoming:
                sys.stdout.write(incoming.decode("ascii", errors="replace"))
                sys.stdout.flush()

            # Poll all mapped keys at ~60 Hz and transmit press/release deltas
            for vk, ch in KEY_MAP.items():
                is_down = (GetAsyncKeyState(vk) & 0x8000) != 0
                if is_down != pressed_state[vk]:
                    pressed_state[vk] = is_down
                    prefix = "+" if is_down else "-"
                    ser.write((prefix + ch).encode("ascii"))

            time.sleep(0.016)
    except KeyboardInterrupt:
        # Release any held keys cleanly on exit
        for vk, ch in KEY_MAP.items():
            if pressed_state[vk]:
                ser.write(("-" + ch).encode("ascii"))
        print("\nController stopped.")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
