#!/bin/bash
# Builds the verilator model of the machine (the ghdl netlist of the VHDL of vic20.prj, its Verilog
# files, tb_vic20.v) and runs sim_vic20 with the given arguments (see sim_vic20.cpp). From
# core-apple2. The build goes to src/sim/build.
#   sim/run_boot.sh --ms 2500 --text --expect "BYTES FREE"
set -e
cd "$(dirname "$0")"
SIM=$(pwd)
SRC=..
mkdir -p build
VHD=$(sed -n 's/^vhdl work "\(.*\)"/\1/p' $SRC/vic20.prj | sed "s#^#$SRC/#")
VLOG=$(sed -n 's/^verilog work "\(.*\)"/\1/p' $SRC/vic20.prj)
VLOG="$VLOG rtl/sv2v/scandoubler.v"
NET=build/vic20_core_ghdl.v
if [ ! -f $NET ] || [ -n "$(find $VHD vhdl2v.sh bb_comp.py -newer $NET 2>/dev/null)" ]; then
	./vhdl2v.sh build > build/ghdl.log 2>&1 || { grep -v warning build/ghdl.log | tail -30; exit 1; }
fi
BIN=build/obj/Vtb_vic20
if [ ! -x $BIN ] || [ -n "$(find $NET $(echo "$VLOG" | sed "s#^#$SRC/#") tb_vic20.v sim_vic20.cpp run_boot.sh -newer $BIN 2>/dev/null)" ]; then
	# the ROM paths of the sources are relative to src/, where XST runs
	(cd $SRC && verilator -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-MULTIDRIVEN \
		-Wno-COMBDLY -Wno-UNOPTFLAT --no-timing +1364-2005ext+v --top-module tb_vic20 \
		-Mdir sim/build/obj --cc $VLOG sim/build/vic20_core_ghdl.v sim/tb_vic20.v \
		--exe $SIM/sim_vic20.cpp -CFLAGS -std=c++17 -o Vtb_vic20 > sim/build/verilator.log 2>&1) || { tail -30 build/verilator.log; exit 1; }
	make -s -j8 -C build/obj -f Vtb_vic20.mk > build/make.log 2>&1 || { tail -30 build/make.log; exit 1; }
fi
# run from src/ so that the $readmem paths (rom/...) resolve
cd $SRC
exec sim/build/obj/Vtb_vic20 "$@"
