#!/usr/bin/env python3
"""Make sim/bios.hex (one 16-bit word a line, for $readmemh) from rtl/bios.mif."""
import re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
mif = os.path.join(here, "..", "rtl", "bios.mif")
txt = open(mif).read()
depth = int(re.search(r"DEPTH\s*=\s*(\d+)", txt).group(1))
words = [0] * depth
for line in txt.split("CONTENT BEGIN")[1].splitlines():
    m = re.match(r"\s*\[?([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\]?\s*:\s*(.*);", line)
    if not m:
        continue
    a = int(m.group(1), 16)
    vals = [int(v, 16) for v in m.group(3).split()]
    if m.group(2):
        for i in range(a, int(m.group(2), 16) + 1):
            words[i] = vals[0]
    else:
        for k, v in enumerate(vals):
            words[a + k] = v
with open(os.path.join(here, "bios.hex"), "w") as f:
    f.write("\n".join("%04X" % w for w in words) + "\n")
print("bios.hex: %d words" % depth)
