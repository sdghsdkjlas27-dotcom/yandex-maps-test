#!/usr/bin/env python3
"""Find the search submit button in a uiautomator dump and print its tap center."""
import re
import sys
import xml.etree.ElementTree as ET

TEXT_OK = re.compile(r"^(search|найти|поиск)$", re.I)
DESC_OK = re.compile(r"(?i)^(search|найти|поиск)$")
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
        cls = n.get("class") or ""
        if not (TEXT_OK.match(text) or DESC_OK.match(desc)):
            continue
        if cls.lower().endswith("edittext"):
            continue  # that's the input field, not the button
        m = BOUNDS.search(n.get("bounds", "") or "")
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        w, h = x2 - x1, y2 - y1
        if w <= 10 or h <= 10 or w * h > 400000:
            continue
        cands.append(((x1 + x2) // 2, (y1 + y2) // 2, text, desc, w, h))
        print(f"candidate: text={text!r} desc={desc!r} size={w}x{h} center=({(x1+x2)//2},{(y1+y2)//2})",
              file=sys.stderr)

    if not cands:
        print("NO_MATCH")
        return 1
    best = max(cands, key=lambda c: c[4] * c[5])
    print(f"{best[0]} {best[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
