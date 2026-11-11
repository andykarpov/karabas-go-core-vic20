#!/usr/bin/env python3
"""bin2hex.py <in.bin> <out.hex>: a ROM image as a $readmemh file (one byte per line), the
INIT_FILE of kg_sprom / kg_sdpram (modules/rtl/mem)."""
import sys

data = open(sys.argv[1], 'rb').read()
with open(sys.argv[2], 'w') as f:
    for b in data:
        f.write('%02x\n' % b)
