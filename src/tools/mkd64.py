#!/usr/bin/env python3
"""mkd64.py: a D64 image (35 tracks, 683 sectors) with PRG files, for tests.

usage: mkd64.py out.d64 [--name DISKNAME] [--id ID] file.prg[=NAME]...

The BAM and the directory as a 1541 formats them (track 18; files from track 17 down and
19 up, interleave 10, as CBM DOS), names in PETSCII upper case.
"""
import sys

SPT = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5   # sectors per track 1..35


def off(t, s):
    return (sum(SPT[:t - 1]) + s) * 256


def pet(name, n=16):
    b = name.upper().encode('ascii')[:n]
    return b + b'\xa0' * (n - len(b))


def main():
    args = sys.argv[1:]
    out = args.pop(0)
    dname, did, files = 'KARABAS', 'KG', []
    while args:
        a = args.pop(0)
        if a == '--name':
            dname = args.pop(0)
        elif a == '--id':
            did = args.pop(0)
        else:
            path, _, name = a.partition('=')
            files.append((path, name or path.rsplit('/', 1)[-1].rsplit('.', 1)[0]))
    img = bytearray(off(36, 0))
    used = {(18, 0), (18, 1)}
    # the order of the tracks for files: 17, 19, 16, 20, ...
    order = [t for d in range(1, 18) for t in (18 - d, 18 + d) if 1 <= t <= 35]
    entries = []
    for path, name in files:
        data = open(path, 'rb').read()
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        secs = []
        for t in order:
            s = 0
            while len(secs) < len(chunks):
                tried = 0
                while (t, s) in used and tried < SPT[t - 1]:
                    s = (s + 1) % SPT[t - 1]
                    tried += 1
                if (t, s) in used:
                    break
                used.add((t, s))
                secs.append((t, s))
                s = (s + 10) % SPT[t - 1]
            if len(secs) == len(chunks):
                break
        for i, (c, (t, s)) in enumerate(zip(chunks, secs)):
            o = off(t, s)
            if i + 1 < len(secs):
                img[o], img[o + 1] = secs[i + 1]
            else:
                img[o], img[o + 1] = 0, len(c) + 1
            img[o + 2:o + 2 + len(c)] = c
        entries.append((secs[0], name, len(secs)))
    # directory (8 entries per sector, track 18 from sector 1)
    assert len(entries) <= 8, 'one directory sector only'
    o = off(18, 1)
    img[o], img[o + 1] = 0, 0xFF
    for i, ((t, s), name, n) in enumerate(entries):
        e = o + i * 32
        img[e + 2] = 0x82                      # PRG, closed
        img[e + 3], img[e + 4] = t, s
        img[e + 5:e + 21] = pet(name)
        img[e + 30], img[e + 31] = n & 255, n >> 8
    # BAM
    b = off(18, 0)
    img[b:b + 4] = bytes([18, 1, 0x41, 0])
    for t in range(1, 36):
        free = [s for s in range(SPT[t - 1]) if (t, s) not in used]
        bits = sum(1 << s for s in free)
        img[b + 4 * t:b + 4 * t + 4] = bytes([len(free), bits & 255, bits >> 8 & 255, bits >> 16 & 255])
    img[b + 0x90:b + 0xA0] = pet(dname)
    img[b + 0xA0:b + 0xA2] = b'\xa0\xa0'
    img[b + 0xA2:b + 0xA4] = did.upper().encode('ascii')[:2].ljust(2, b' ')
    img[b + 0xA4] = 0xA0
    img[b + 0xA5:b + 0xA7] = b'2A'
    img[b + 0xA7:b + 0xAB] = b'\xa0' * 4
    open(out, 'wb').write(img)


main()
