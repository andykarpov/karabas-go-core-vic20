#!/bin/bash
# tb_nvram.v: vic20_nvram on a model of the img_sdc requests (iverilog, seconds).
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2005 -o sim/build/tb_nvram sim/tb_nvram.v rtl/karabas/vic20_nvram.v ../modules/rtl/mem/kg_tdpram.v
vvp -n sim/build/tb_nvram | grep -v '^VCD'
