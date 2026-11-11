#!/usr/bin/env python3
"""prg2tap.py: a .prg as a .tap (version 1) in the format of the CBM Kernal (VIC-20 / C64
datasette), for tests of the tape player.

usage: prg2tap.py in.prg out.tap [NAME] [--type 1|3]

A block (header: 192 bytes, data: the program) is written twice: a leader of short pulses, the
countdown $89..$81 (repeat: $09..$01), the bytes, their XOR, the end marker. A byte: the
new-data marker (long, medium), 8 bits LSB first and an odd parity bit, bit 0 = (short, medium),
bit 1 = (medium, short). Pulse lengths in TAP units (8 clocks of the machine): the usual
0x30 / 0x42 / 0x56. Header: type 1 (relocatable BASIC, LOAD puts it at the start of BASIC)
or 3 (at its own address), start, end + 1, the name padded with spaces.
"""
import sys

S, M, L = 0x30, 0x42, 0x56


def byte_pulses(b):
    p = [L, M]
    ones = 0
    for i in range(8):
        bit = b >> i & 1
        ones += bit
        p += [M, S] if bit else [S, M]
    parity = 1 if ones % 2 == 0 else 0
    p += [M, S] if parity else [S, M]
    return p


def block(data, leader, repeat):
    p = [S] * leader
    for c in (range(0x09, 0x00, -1) if repeat else range(0x89, 0x80, -1)):
        p += byte_pulses(c)
    x = 0
    for b in data:
        p += byte_pulses(b)
        x ^= b
    p += byte_pulses(x)
    p += [L, S]          # end of data
    return p


def main():
    args = sys.argv[1:]
    ftype = 1
    if '--type' in args:
        i = args.index('--type')
        ftype = int(args[i + 1])
        del args[i:i + 2]
    src, dst = args[0], args[1]
    name = (args[2] if len(args) > 2 else src.rsplit('/', 1)[-1].rsplit('.', 1)[0]).upper()
    prg = open(src, 'rb').read()
    start = prg[0] | prg[1] << 8
    body = prg[2:]
    end = start + len(body)
    hdr = bytes([ftype, start & 255, start >> 8, end & 255, end >> 8])
    hdr += name.encode('ascii')[:16].ljust(16, b' ')
    hdr = hdr.ljust(192, b' ')
    pulses = []
    pulses += block(hdr, 0x2000, False)      # ~3 s of leader before the header
    pulses += block(hdr, 0x4F, True)
    pulses += [S] * 0x4F
    pulses += block(body, 0x1000, False)
    pulses += block(body, 0x4F, True)
    pulses += [S] * 0x4F
    raw = bytes(pulses)
    out = b'C64-TAPE-RAW' + bytes([1, 0, 0, 0]) + len(raw).to_bytes(4, 'little') + raw
    open(dst, 'wb').write(out)
    print('%s: %s %04x-%04x, %d pulses' % (dst, name, start, end, len(raw)))


main()
