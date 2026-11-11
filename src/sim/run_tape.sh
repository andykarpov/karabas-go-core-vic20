#!/bin/bash
# tb_tape.v: vic20_loader + vic20_tape + vic20_sram on a model of the SRAM (iverilog, seconds).
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2005 -o sim/build/tb_tape sim/tb_tape.v rtl/karabas/vic20_loader.v rtl/karabas/vic20_tape.v rtl/karabas/vic20_sram.v
vvp -n sim/build/tb_tape
