#!/usr/bin/env python3
"""Find the Yandex Maps search field in a uiautomator dump and print its tap center."""
import re
import sys
import xml.etree.ElementTree as ET

PATTERN = re.compile(r"(?i)(search|поиск)")
BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def nodes(root):
    yield root
    for child in root:
        yield from nodes(child)


def main(path):
    tree = ET.parse(path)
    candidates = []
    for n in nodes(tree.getroot()):
        text = n.get("text", "") or ""
        desc = n.get("content-desc", "") or ""
        rid = n.get("resource-id", "") or ""
        hay = f"{text} {desc} {rid}"
        if not PATTERN.search(hay):
            continue
        # skip bottom-bar icons etc. that are just "search"-labelled images
        # prefer visible, reasonably sized nodes
        m = BOUNDS.search(n.get("bounds", "") or "")
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 <= x1 or y2 <= y1:
            continue
        w, h = x2 - x1, y2 - y1
        candidates.append((w * h, w, h, (x1 + x2) // 2, (y1 + y2) // 2, text, desc, rid))

    if not candidates:
        print("NO_MATCH")
        return 1

    for c in candidates:
        print(f"candidate: size={c[0]} text={c[5]!r} desc={c[6]!r} rid={c[7]!r} center=({c[3]},{c[4]})", file=sys.stderr)

    # prefer a node whose text/desc mentions search and that is wide (an input field)
    def score(c):
        _, w, h, *rest = c
        text = (c[5] + " " + c[6]).lower()
        s = 0
        if "search here" in text or "поиск здесь" in text:
            s += 1000
        if w > 300:
            s += 500
        if h < 300:
            s += 200
        return s + w

    best = max(candidates, key=score)
    print(f"{best[3]} {best[4]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
