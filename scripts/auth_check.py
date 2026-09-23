#!/usr/bin/env python3
"""Decide whether Yandex Maps is authenticated, based on UI dump + foreground package."""
import os
import re
import sys

LOGIN_PAT = re.compile(r"(войти|log ?in|sign ?in|авторизац)", re.I)
WEBVIEW_PAT = re.compile(r"(passport|подтвердите вход|войти по qr|qr-код|введите код|SMS-код|смс-код)", re.I)
APP = "ru.yandex.yandexmaps"


def main(path):
    focus = (os.environ.get("FOCUS") or "").lower()
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            txt = f.read().lower()
    except OSError:
        txt = ""

    login = bool(LOGIN_PAT.search(txt))
    webview = bool(WEBVIEW_PAT.search(txt))
    in_app = APP in focus
    browser = any(b in focus for b in ("chrome", "browser", "webview")) and APP not in focus

    if in_app and not login and not webview and not browser:
        print("AUTHENTICATED")
        return 0
    reasons = []
    if login:
        reasons.append("login_marker")
    if webview:
        reasons.append("auth_screen")
    if not in_app:
        reasons.append(f"focus={focus or 'unknown'}")
    print("WAITING " + ",".join(reasons))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
