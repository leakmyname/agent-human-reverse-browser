#!/bin/sh
# 拉起 Chromium（带 CDP 调试口）+ CDP 桥
export DISPLAY=:1
export HOME=/config

LOGDIR=/config/logs
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=/tmp

CHROME_FLAGS="--no-sandbox --no-first-run --disable-dev-shm-usage --password-store=basic
--disable-gpu --disable-features=Translate,MediaRouter
--window-size=1920,1080 --window-position=0,0
--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --remote-allow-origins=*
--user-data-dir=/config/chrome-profile"

rm -f /config/chrome-profile/SingletonLock \
      /config/chrome-profile/SingletonCookie \
      /config/chrome-profile/SingletonSocket 2>/dev/null

/usr/bin/chromium $CHROME_FLAGS "$@" >"$LOGDIR/chromium.log" 2>&1 &

# 等 CDP 就绪后再起桥
i=0
while [ $i -lt 30 ]; do
    if wget -qO- http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

exec python3 /opt/webtop-reverse/cdp-bridge.py
