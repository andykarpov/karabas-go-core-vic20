#!/bin/bash
# Converts the SystemVerilog of upstream (mist_sd_card.sv of the C1541; scandoubler.v of the board
# tops, which uses SV) to Verilog-2001 for XST with sv2v (/opt/sv2v/sv2v): one file per module in
# rtl/sv2v/. rtl/sv2v/ is generated and in git; change the sources (with a "karabas:" comment),
# then run this.
set -e
cd "$(dirname "$0")/../rtl"
SV2V=${SV2V:-/opt/sv2v/sv2v}
SRC="c1541/mist_sd_card.sv misc/scandoubler.v"
rm -rf sv2v && mkdir sv2v
$SV2V --top=mist_sd_card --top=scandoubler $SRC -w sv2v 2>&1 | grep -v -E '^\s*$' || true
ls sv2v
