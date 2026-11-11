#!/bin/bash
# tb_hid.v: vic20_hid + the keymap (iverilog, seconds).
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2005 -o sim/build/tb_hid sim/tb_hid.v rtl/karabas/vic20_hid.v rtl/misc/vic20_keymap.v
vvp -n sim/build/tb_hid
