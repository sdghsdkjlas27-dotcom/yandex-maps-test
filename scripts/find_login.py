#!/usr/bin/env python3
"""Find login/profile or menu elements in a uiautomator dump. Prints tap center."""
import os
import re
import sys
import xml.etree.ElementTree as ET

MODE = os.environ.get("MODE", "login")
BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")

LOGIN_PAT = re.compile(r"(?i)(^войти$|^log ?in$|^sign ?in$|войти|аккаунт|account|профиль|profile|авторизац)")
MENU_PAT = re.compile(r"(?i)(меню|menu|navigation drawer|открыть список)")


def nodes(root):
    yield root
    for child in root:
        yield from nodes(child)


def main(path):
    mode = sys.argv[1] if len(sys.argv) > 1 else MODE
    pat = MENU_PAT if mode == "menu" else LOGIN_PAT
    tree = ET.parse(path)
    cands = []
    for n in nodes(tree.getroot()):
        text = (n.get("text") or "").strip()
        desc = (n.get("content-desc") or "").strip()
        cls = n.get("class") or ""
        if "mapview" in cls.lower():
            continue
        m = pat.search(text) or pat.search(desc)
        if not m:
            continue
        bm = BOUNDS.search(n.get("bounds", "") or "")
        if not bm:
            continue
        x1, y1, x2, y2 = map(int, bm.groups())
        w, h = x2 - x1, y2 - y1
        if w <= 5 or h <= 5 or h > 500:
            continue
        exact = bool(re.match(r"(?i)^(войти|log ?in|sign ?in)$", text or desc))
        cands.append((1000 * exact + w, (x1 + x2) // 2, (y1 + y2) // 2, text, desc, w, h))
        print(f"cand: exact={exact} text={text!r} desc={desc!r} size={w}x{h}",
              file=sys.stderr)
    if not cands:
        print("NO_MATCH")
        return 1
    best = max(cands, key=lambda c: c[0])
    print(f"{best[1]} {best[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))
