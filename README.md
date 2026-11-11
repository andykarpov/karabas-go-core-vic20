# Commodore VIC-20 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

A Commodore VIC-20 for the Karabas Go family of boards (Xilinx Spartan-6 XC6SLX25): a port of
[VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano) (MiSTle-Dev), itself the MiST / MiSTer VIC-20
of MikeJ and WoS with the C1541 drive of darfpga. All file work (programs, cartridges, disk images,
tapes, ROMs) goes through the OSD and the file browser of the board firmware: the core has no
loader of its own. A user guide (Russian) is in `docs/GUIDE.md`, the plan and the decisions in
`docs/PLAN.md` (Russian).

| Board | Core file | Video | Audio | State |
|---|---|---|---|---|
| Karabas Mini G | `vic20.kg` | HDMI, 720x576 50 Hz (PAL) / 720x480 60 Hz (NTSC) | HDMI, I2S DAC (PCM5102) | tested on hardware |
| Karabas Mini | `vic20.kg` | HDMI, as Mini G | HDMI, analog output (sigma-delta) | built, not tested on hardware |
| Karabas Go | `vic20.kg` | VGA, as Mini G | I2S DAC (PCM5102) | built, not tested on hardware |

The core file is `src/vic20.kg`, one file for all three boards, with the Commodore ROMs built in.
It needs the firmware v26103113 or later. The OSD items look for files in `/vic20` on the SD card.

## What it does

- **The machine:** 6502 (T65) at 1.1 MHz (PAL) / 1.02 MHz (NTSC), the VIC 6561 (PAL) or 6560
  (NTSC) with its sound, two 6522 VIAs, 5 KB of RAM, BASIC V2 and the Kernal of the standard
  (901486-07 PAL / 901486-06 NTSC). PAL or NTSC is the OSD item Video (the machine restarts).
- **RAM expansions:** 3K, 8K, 16K, 24K, 3K+24K, 35K (the OSD item RAM), in the SRAM of the board.
- **Programs:** a `.prg` is put into the memory of the running machine at its load address, with
  the BASIC pointers set after it: `RUN` or `LIST` at once.
- **Cartridges:** a file with its two-byte load address (`.prg`, `.a0`, `.crt` as MiSTer takes
  them), 8 KB or more, in the blocks $2000 / $4000 / $6000 / $A000 (read only); a cartridge at
  $A000 starts by itself. Eject cart (Menu+E) removes it.
- **Mega-Cart:** a 2 MB Mega-Cart image (`.rom`, `.bin`) in the SRAM, with its menu.
- **Disk drive 8:** a C1541 (6502, two VIAs, the DOS ROM 325302-01 / 901229-06AA) on `.d64` and
  `.g64` images, reads and writes (writes go to the image file); a read only file or Disk 8 WP is
  a write protected disk. Another DOS ROM (16 KB, or the last 16 KB of a 32 KB image) can be loaded
  from a file (1541 DOS).
- **Datasette:** `.tap` files (up to 1 MB) played into a C1530; PLAY is pressed when the file is
  chosen, so `LOAD` finds the program at once; Tape play (Menu+P) is the PLAY / STOP key.
- **Kernal:** another 8 KB Kernal from a file (for example JiffyDOS) replaces the built-in one.
- **Input:** the USB keyboard as the VIC-20 keyboard (Symbolic or Positional layout, see below),
  the joystick of the board or a USB gamepad as the joystick, the USB mouse as two paddles (the OSD
  item Mouse).
- **Video:** the picture of the VIC doubled to 576p50 / 480p60, centred, with the OSD.

Checked on the Mini G: BASIC, both keyboard layouts, PRG / cartridge / RAM expansions, PAL and
NTSC, sound, D64 directory, `LOAD` and `SAVE` (the file lands in the image), TAP loading, Mega-Cart
with Eject, a DOS ROM from a file, the paddles. Not there: a second drive, cartridges of several files, saving the Mega-Cart
NVRAM, the RS-232 of the user port, tape recording.

## OSD

The OSD opens with Menu+Esc ("Menu" is the Windows key).

| Item | What it does | Hotkey |
|---|---|---|
| Disk 8 | the disk image of drive 8 (`.d64`, `.g64`) | Menu+F1 |
| PRG | a program into the memory | Menu+F2 |
| Cartridge | a cartridge file (the machine restarts with it) | Menu+F3 |
| Tape | a `.tap` file into the datasette | Menu+F4 |
| Kernal | an 8 KB Kernal file instead of the built-in one | Menu+F5 |
| Mega-Cart | a 2 MB Mega-Cart image | Menu+F6 |
| 1541 DOS | a DOS ROM file of the drive | Menu+F7 |
| RAM | None / 3K / 8K / 16K / 24K / 3K+24K / 35K (then Reset) | Menu+M |
| Video | PAL / NTSC | Menu+V |
| Keyboard | Symbolic / Positional | Menu+K |
| Mouse | Off / Paddles | |
| Disk 8 WP | Off / On: write protect of the disk | |
| Tape play | the PLAY / STOP key of the datasette | Menu+P |
| Eject cart | removes the cartridge or the Mega-Cart (and restarts) | Menu+E |
| Reset | restarts the machine | Menu+F12 |

## Keyboard

Symbolic (the default): a character typed on a US PC keyboard is the same character on the VIC
(`Shift+=` gives `+`, `Shift+;` gives `:`, `'` and `"` are the VIC `Shift+7` / `Shift+2`).
Positional: the keys of the PC in the places of the VIC keys, the PC Shift as it is (as upstream).

| VIC-20 | PC |
|---|---|
| RUN/STOP | Esc |
| RESTORE | F11 |
| C= (Commodore) | Alt, Caps Lock |
| CTRL | Ctrl |
| CLR/HOME | Home |
| INST/DEL | Backspace, Delete (Insert: INST) |
| f1 / f3 / f5 / f7 | F1 / F3 / F5 / F7 (F2 / F4 / F6 / F8: with Shift) |
| £ | \ |
| ← | ` |
| ↑ | F9 |
| cursor keys | the arrows |

## Building

The core is built with Xilinx ISE 14.7 on Linux: `cd src && make` (all three boards, one after the
other), or `make go`, `make mini`, `make minig`; `make minig-report` shows the utilization and the
timing of the last build. The Mini G top is the one that is edited: `src/tools/mktops.py` makes the
Go and Mini tops from it (the Makefile runs it). The board modules are the submodule `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): clone with
`git clone --recursive` or run `git submodule update --init`. Packing the `.kg` file needs the
sibling repo [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one.

The simulations are in `src/sim`: the whole machine in verilator (`run_boot.sh`, ghdl for the VHDL:
boot, a PRG with `RUN`, the screen read as text), iverilog tests of the loader, the keyboard and the
tape (`run_loader.sh`, `run_hid.sh`, `run_tape.sh`). `src/tools/mkd64.py` and `prg2tap.py` make
test disk and tape images. `CLAUDE.md` has the layout and the rules of the design.

The board firmware is [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Credits and license

- [VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano): MiSTle-Dev (the Tang port, the Mega-Cart,
  the C1530 tape player).
- The VIC-20 of MikeJ (fpgaarcade) and WoS (MiST / MiSTer); T65: Daniel Wallner, MikeJ and others.
- The C1541 of darfpga.
- Karabas Go boards and the port: Andy Karpov.

VIC20Nano is GPL v3; the Karabas parts are GPL v3 (`LICENSE`). Imported files keep their own
headers. The Commodore ROMs in `src/rom` (BASIC, Kernal, the character ROM, the 1541 DOS) are those
that MiSTer VIC20_MiSTer ships; they are built into the core file.
