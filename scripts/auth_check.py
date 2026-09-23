#!/usr/bin/env python3
"""Decide whether Yandex Maps is authenticated.

Strict requirements (no false positives):
  1. marker file .auth_screen_seen exists  -> the auth screen was really shown
  2. current foreground is the maps app, not a browser/webview activity
  3. current dump has NO login/auth markers
  4. current dump DOES look like the main map (search field / map controls)
"""
import os
import re
import sys

MARKER = ".auth_screen_seen"
LOGIN_PAT = re.compile(r"(войти|вход\b|вход в|логин|log ?in|sign ?in|авторизац|qr-код|введите.*код)", re.I)
MAP_PAT = re.compile(r"(search here|поиск здесь|search_line|моё местоположение|увеличить масштаб)", re.I)
APP = "ru.yandex.yandexmaps"


def main(path):
    focus = (os.environ.get("FOCUS") or "").lower()
    if not os.path.exists(MARKER):
        print("WAITING no auth screen seen yet")
        return 1
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            txt = f.read().lower()
    except OSError:
        txt = ""

    login = bool(LOGIN_PAT.search(txt))
    on_map = bool(MAP_PAT.search(txt))
    in_app = APP in focus and not any(b in focus for b in ("chrome", "browser"))
    auth_activity = ("auth" in focus or "passport" in focus or "webview" in focus)

    if in_app and not auth_activity and not login and on_map:
        print("AUTHENTICATED")
        return 0
    reasons = []
    if login:
        reasons.append("login_markers")
    if auth_activity:
        reasons.append("auth_activity")
    if not on_map:
        reasons.append("no_map_ui")
    if not in_app:
        reasons.append(f"focus={focus or 'unknown'}")
    print("WAITING " + ",".join(reasons))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
