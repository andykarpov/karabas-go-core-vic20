#!/bin/bash
# The VHDL of the machine (vic20_core and below) as one Verilog netlist for verilator: ghdl --synth,
# the Verilog modules it instantiates left as black boxes (components of bb_comp.py for the ones
# taken with "entity work.", the kg_* memories have component declarations in the VHDL already).
# From core-apple2. Run from anywhere.
#   sim/vhdl2v.sh <out dir>   -> <out dir>/vic20_core_ghdl.v
set -eu
OUT=$(mkdir -p "${1:?output dir}" && cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/.." && pwd)
cd "$SRC"
mkdir -p "$OUT/vhd"
VHD=$(sed -n 's/^vhdl work "\(.*\)"/\1/p' vic20.prj)
python3 sim/bb_comp.py "$OUT/vhd" mist_sd_card=rtl/sv2v/mist_sd_card.v -- $VHD
cd "$OUT/vhd"
G="--std=08 -fsynopsys -frelaxed"
rm -f work-obj08.cf
ghdl -a $G sim_bb.vhd
for f in $VHD; do ghdl -a $G "$(basename "$f")"; done
ghdl --synth $G --out=verilog vic20_core > ../vic20_core_ghdl.v
wc -l ../vic20_core_ghdl.v
