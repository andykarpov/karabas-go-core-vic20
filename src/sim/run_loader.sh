#!/bin/bash
# tb_loader.v: vic20_loader + vic20_sram on a model of the SRAM (iverilog, seconds).
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2005 -o sim/build/tb_loader sim/tb_loader.v rtl/karabas/vic20_loader.v rtl/karabas/vic20_sram.v
vvp -n sim/build/tb_loader | grep -v '^VCD'
