# webtop-reverse: linuxserver/webtop + Chromium(remote debugging) + CDP bridge
# 用途：我方通过 noVNC 人工登录目标站点，agent 通过 CDP 接管同一浏览器做 API 逆向
FROM lscr.io/linuxserver/webtop:alpine-openbox

COPY cdp-bridge.py /opt/webtop-reverse/cdp-bridge.py
COPY start-browser.sh /opt/webtop-reverse/start-browser.sh
RUN chmod +x /opt/webtop-reverse/start-browser.sh

# linuxserver 的 s6 会以 abc 用户执行 /defaults/startwm.sh，这里在 openbox 之后拉起浏览器
RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    '/usr/bin/openbox-session' \
    '/opt/webtop-reverse/start-browser.sh >/tmp/browser.log 2>&1 &' \
    > /defaults/startwm.sh && \
    chmod +x /defaults/startwm.sh

# 预建浏览器数据目录并交给 abc，否则挂载卷后 Chromium 无法写 profile（SingletonLock 权限问题）
RUN mkdir -p /config/chrome-profile /config/logs && \
    chown -R abc:abc /config/chrome-profile /config/logs

EXPOSE 3000 3001 9223
