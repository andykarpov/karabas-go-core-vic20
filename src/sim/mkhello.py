#!/usr/bin/env python3
"""mkhello.py out.prg [start hex]: 10 PRINT"HELLO VIC": 20 GOTO 10 as a tokenized BASIC PRG
(start $1001: unexpanded and +3K... use 1201 with 8K or more)."""
import sys

start = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x1001
lines = [(10, b'\x99"HELLO VIC"'), (20, b'\x89 10')]   # PRINT, GOTO
body, a = b'', start
for n, t in lines:
    ln = bytes([n & 255, n >> 8]) + t + b'\0'
    a += 2 + len(ln)
    body += bytes([a & 255, a >> 8]) + ln
body += b'\0\0'
open(sys.argv[1], 'wb').write(bytes([start & 255, start >> 8]) + body)
