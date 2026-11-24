#!/bin/sh
# 拉起 Chromium（带 CDP 调试口）+ CDP 端口桥
#
# --remote-debugging-port=0 让 Chromium 随机分配端口，并把实际端口写进
# user-data-dir/DevToolsActivePort。这样 Chrome DevTools MCP 的 --autoConnect
# 就能按官方机制（读 DevToolsActivePort）找到浏览器，无需写死端口。
export DISPLAY=:1
export HOME=/config

PROFILE=/config/chrome-profile
LOGDIR=/config/logs
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=/tmp

CHROME_FLAGS="--no-sandbox --no-first-run --disable-dev-shm-usage --password-store=basic
--disable-features=Translate,MediaRouter
--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader
--window-size=1920,1080 --window-position=0,0
--remote-debugging-address=127.0.0.1 --remote-debugging-port=0 --remote-allow-origins=*
--user-data-dir=$PROFILE"

start_chrome() {
    rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonCookie" "$PROFILE/SingletonSocket" 2>/dev/null
    /usr/bin/chromium $CHROME_FLAGS "$@" >>"$LOGDIR/chromium.log" 2>&1 &
}

start_chrome

# 等 DevToolsActivePort 出现（即 CDP 就绪）
i=0
while [ $i -lt 30 ]; do
    [ -f "$PROFILE/DevToolsActivePort" ] && break
    i=$((i + 1))
    sleep 1
done

[ -f "$PROFILE/DevToolsActivePort" ] && \
    echo "cdp ready: $(head -1 "$PROFILE/DevToolsActivePort")" >&2

# CDP 桥：0.0.0.0:9223 -> Chromium 随机端口
python3 /opt/webtop-reverse/cdp-bridge.py >>"$LOGDIR/bridge.log" 2>&1 &

# 常驻守护：Chromium 崩了或被关掉时重新拉起。
# 本脚本必须常驻，否则 s6 的 svc-watchdog 会重启整个 autostart。
while true; do
    if ! pgrep -u abc chromium >/dev/null 2>&1; then
        echo "chromium died, restarting..." >&2
        rm -f "$PROFILE/DevToolsActivePort"
        start_chrome
        sleep 5
    fi
    sleep 3
done
