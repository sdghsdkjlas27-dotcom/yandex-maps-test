#!/usr/bin/env python3
"""Find QR-login related elements in a uiautomator dump. Prints tap center."""
import re
import sys
import xml.etree.ElementTree as ET

QR_PAT = re.compile(r"(?i)qr")
BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def nodes(root):
    yield root
    for child in root:
        yield from nodes(child)


def main(path):
    tree = ET.parse(path)
    cands = []
    for n in nodes(tree.getroot()):
        text = (n.get("text") or "").strip()
        desc = (n.get("content-desc") or "").strip()
        m = QR_PAT.search(text) or QR_PAT.search(desc)
        if not m:
            continue
        bm = BOUNDS.search(n.get("bounds", "") or "")
        if not bm:
            continue
        x1, y1, x2, y2 = map(int, bm.groups())
        w, h = x2 - x1, y2 - y1
        if w <= 5 or h <= 5:
            continue
        cands.append((w * h, (x1 + x2) // 2, (y1 + y2) // 2, text, desc))
        print(f"cand: text={text!r} desc={desc!r} size={w}x{h} center=({(x1+x2)//2},{(y1+y2)//2})",
              file=sys.stderr)
    if not cands:
        print("NO_MATCH")
        return 1
    best = max(cands, key=lambda c: c[0])
    print(f"{best[1]} {best[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
