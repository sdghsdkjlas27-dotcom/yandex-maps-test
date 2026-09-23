#!/usr/bin/env python3
"""Detect whether the auth/login screen is currently shown.

Prints YES/NO plus a reason. On YES, creates marker file .auth_screen_seen.
"""
import glob
import os
import re
import sys

MARKER = ".auth_screen_seen"
AUTH_PAT = re.compile(
    r"(passport|вход\b|вход в|войти по|войти$|^войти|логин|log ?in|sign ?in|"
    r"введите.*код|qr-код|авторизац|продолжить)",
    re.I | re.M,
)
APP = "ru.yandex.yandexmaps"


def main(xml_path, focus):
    try:
        with open(xml_path, encoding="utf-8", errors="replace") as f:
            txt = f.read()
    except OSError:
        txt = ""
    low = txt.lower()
    focus_l = (focus or "").lower()

    markers = bool(AUTH_PAT.search(low))
    # auth flows often run in a different activity or a browser
    activity_change = bool(focus_l) and APP in focus_l and (
        "auth" in focus_l or "passport" in focus_l or "webview" in focus_l
    )
    browser = any(b in focus_l for b in ("chrome", "browser")) and APP not in focus_l

    if markers or activity_change or browser:
        open(MARKER, "w").close()
        print(f"YES markers={markers} activity_change={activity_change} browser={browser}")
        return 0
    print(f"NO markers={markers} focus={focus_l or 'unknown'}")
    return 1


if __name__ == "__main__":
    focus = sys.argv[2] if len(sys.argv) > 2 else ""
    sys.exit(main(sys.argv[1], focus))
