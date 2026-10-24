#!/usr/bin/env python3
"""Make vm1_plm_sim.v from rtl/VM1/vm1_plm.v for Verilator: its PLM matrix
compares against patterns with x bits through a casex on a function
argument, which a two-state simulator cannot do; here every pattern becomes
an explicit mask/value compare."""
import re, os
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "rtl", "VM1", "vm1_plm.v")).read()
pat = re.compile(r"cmp\(\{([a-z]+), ([a-z]+)\}, \{(\d+)'b([01x]+), (\d+)'b([01x]+)\}\)")
n = 0
def sub(m):
    global n
    n += 1
    bits = m.group(4) + m.group(6)
    w = int(m.group(3)) + int(m.group(5))
    assert len(bits) == w, m.group(0)
    mask = "".join("0" if c == "x" else "1" for c in bits)
    val  = "".join("0" if c == "x" else c for c in bits)
    return "(({%s, %s} & %d'b%s) == %d'b%s)" % (m.group(1), m.group(2), w, mask, w, val)
out = pat.sub(sub, src)
left = [l for l in out.splitlines() if "cmp(" in l and "function" not in l]
assert not left, left[:3]
open(os.path.join(here, "vm1_plm_sim.v"), "w").write(out)
print("patterns rewritten:", n)
