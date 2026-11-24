# webtop-reverse: linuxserver/webtop + Chromium(remote debugging) + CDP bridge
# 用途：我方通过 noVNC 人工登录目标站点，agent 通过同一浏览器的 CDP 接管做 API 逆向
#
# 基础镜像用 :latest（Chromium 158 / Selkies / XFCE），满足 Chrome DevTools MCP
# --autoConnect 所需的 Chrome >= 144 版本要求。
FROM lscr.io/linuxserver/webtop:latest

# chromium-angle 提供 ANGLE 的 SwiftShader 软件渲染库（libEGL/libGLESv2/libvulkan）。
# 容器内无 GPU，必须有它，否则页面合成层渲染为空白（在 noVNC 里看不见页面内容）。
# apk 源站在国内经常超时，因此把 apk 包随构建上下文一起带进来离线安装。
COPY apk/ /apk/
RUN apk add --no-network --allow-untrusted /apk/chromium-angle-*.apk && \
    ls -l /usr/lib/chromium/libEGL.so /usr/lib/chromium/libGLESv2.so

COPY cdp-bridge.py /opt/webtop-reverse/cdp-bridge.py
COPY start-browser.sh /opt/webtop-reverse/start-browser.sh
COPY webtop-reverse.desktop /config/.config/autostart/webtop-reverse.desktop
RUN chmod +x /opt/webtop-reverse/start-browser.sh && \
    chmod 644 /config/.config/autostart/webtop-reverse.desktop

# 预建浏览器数据目录并交给 abc，否则挂载卷后 Chromium 无法写 profile
RUN mkdir -p /config/chrome-profile /config/logs && \
    chown -R abc:abc /config/chrome-profile /config/logs /config/.config/autostart

EXPOSE 3000 3001 9223
