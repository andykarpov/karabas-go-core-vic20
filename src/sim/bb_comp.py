#!/usr/bin/env python3
"""For the simulation: component declarations of the Verilog modules that the VHDL instantiates
(ghdl --synth leaves unbound components as black boxes, the Verilog netlist instantiates the real
modules), and copies of the VHDL files with "entity work.<module>" changed to the component.

usage: bb_comp.py <out dir> <module>=<verilog file normalised by sv2v>... -- <vhdl files>
"""
import os
import re
import sys

out = sys.argv[1]
args = sys.argv[2:]
sep = args.index('--')
mods = dict(a.split('=', 1) for a in args[:sep])
vhdl = args[sep + 1:]
PARAMS = {}   # parameters in port widths with the defaults the VHDL keeps


def ports(name, path):
    s = open(path).read()
    m = re.search(r'\bmodule\s+%s\b(.*?)\bendmodule' % re.escape(name), s, re.S)
    assert m, (name, path)
    body = m.group(1)
    res = []
    for d in re.finditer(r'\b(input|output|inout)\s+(?:wire|reg|logic)?\s*(?:signed\s*)?(\[[^\]]+\])?\s*([\w\s,]+?)\s*;', body):
        rng = d.group(2)
        width = None
        if rng:
            hi, lo = rng[1:-1].split(':')
            for k, v in PARAMS.items():
                hi = re.sub(r'\b%s\b' % k, str(v), hi)
            width = (eval(hi), eval(lo))
        for n in d.group(3).split(','):
            res.append((n.strip(), d.group(1), width))
    return res


pk = ['library ieee;', 'use ieee.std_logic_1164.all;', 'package sim_bb is']
for name, path in mods.items():
    pk.append('  component %s' % name)
    pl = []
    for n, d, w in ports(name, path):
        t = 'std_logic' if w is None else 'std_logic_vector(%d downto %d)' % w
        pl.append('    %s : %s %s' % (n, {'input': 'in', 'output': 'out', 'inout': 'inout'}[d], t))
    pk.append('  port (\n' + ';\n'.join(pl) + '\n  );')
    pk.append('  end component;')
pk.append('end package;')
open(os.path.join(out, 'sim_bb.vhd'), 'w').write('\n'.join(pk) + '\n')

names = '|'.join(map(re.escape, mods))
for f in vhdl:
    s = open(f, newline='').read()
    s2, n = re.subn(r'\bentity\s+work\.(%s)\b' % names, r'\1', s, flags=re.I)
    if n:
        # the components are visible to every entity of the file
        s2 = re.sub(r'^(\s*entity\s+\w+\s+is\b)', r'library work; use work.sim_bb.all;\n\1', s2, flags=re.I | re.M)
    # ghdl names the output nets of an instance <label>_<port>: a signal of that name (mcu_pa_out of
    # applemouse) is declared twice in the netlist. Labels with a suffix in the copy.
    s2 = re.sub(r'^(\s*)(\w+)(\s*:\s*(?:entity\s+work\.)?\w+\s+(?:generic|port)\s+map\b)',
                lambda m: m.group(1) + m.group(2) + '_u' + m.group(3)
                if m.group(2).lower() not in ('signal', 'variable', 'constant') else m.group(0),
                s2, flags=re.I | re.M)
    open(os.path.join(out, os.path.basename(f)), 'w', newline='').write(s2)
