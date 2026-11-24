#!/usr/bin/env bash
# 启动一个临时 webtop-reverse 容器，供人工通过 noVNC 登录 + agent 通过 CDP 逆向
# 用法: rev-up.sh [容器名] [起始URL]
set -euo pipefail

NAME="${1:-rev-$(date +%H%M%S)}"
START_URL="${2:-about:blank}"
STATE_DIR="${WEBTOP_REV_STATE:-${TMPDIR:-/tmp}/webtop-reverse}"
IMAGE="${WEBTOP_REV_IMAGE:-webtop-reverse:latest}"
PROXY="${WEBTOP_REV_PROXY:-}"

mkdir -p "$STATE_DIR"
PROFILE_VOL="webtop-rev-${NAME}-profile"
STATE_FILE="$STATE_DIR/${NAME}.json"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "容器 $NAME 已存在，先执行 rev-down.sh $NAME" >&2
  exit 1
fi

# 容器内 127.0.0.1 指向容器自己，要用宿主机桥接地址才能复用宿主代理
BRIDGE_IP="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
GW="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
PROXY="${WEBTOP_REV_PROXY:-http://${BRIDGE_IP:-${GW:-172.17.0.1}}:7893}"

pick_port() {
  python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
}
CDP_PORT="$(pick_port)"
while [ "$CDP_PORT" = "$(pick_port)" ]; do :; done
VNC_PORT="$(pick_port)"

echo "[*] 启动容器 $NAME ..."
docker run -d \
  --name "$NAME" \
  --shm-size=1g \
  -m 1500m \
  --restart=no \
  -p "127.0.0.1:${VNC_PORT}:3000" \
  -p "127.0.0.1:${CDP_PORT}:9223" \
  -e "http_proxy=${PROXY}" -e "https_proxy=${PROXY}" \
  -e "HTTP_PROXY=${PROXY}" -e "HTTPS_PROXY=${PROXY}" \
  -v "${PROFILE_VOL}:/config/chrome-profile" \
  "$IMAGE" >/dev/null

# 等 CDP 就绪（容器内 Chromium 随机端口 -> 桥接固定端口 9223）
for i in $(seq 1 45); do
  if curl -sf --max-time 2 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sf --max-time 3 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  echo "[!] CDP 未就绪，日志：" >&2
  docker logs --tail 30 "$NAME" >&2
  docker exec "$NAME" sh -c 'cat /config/logs/chromium.log 2>/dev/null | tail -20' >&2 || true
  exit 1
fi

# 生成供 chrome-devtools-mcp --autoConnect 使用的 DevToolsActivePort。
# 注意要写「宿主机」CDP 端口，因为 autoConnect 在宿主机侧读这个文件并连 127.0.0.1:<port>；
# 容器内真实端口由 cdp-bridge 转发到宿主机映射端口。
SHIM_DIR="$STATE_DIR/${NAME}-autoconnect"
mkdir -p "$SHIM_DIR"
WS_PATH="$(docker exec "$NAME" sh -c 'sed -n 2p /config/chrome-profile/DevToolsActivePort 2>/dev/null' | tr -d '\r' || true)"
if [ -n "$WS_PATH" ]; then
  printf '%s\n%s\n' "$CDP_PORT" "$WS_PATH" > "$SHIM_DIR/DevToolsActivePort"
fi

# 打开起始页
if [ "$START_URL" != "about:blank" ]; then
  "$(dirname "$0")/cdp-open.py" "http://127.0.0.1:${CDP_PORT}" "$START_URL" >/dev/null 2>&1 || true
fi

cat > "$STATE_FILE" <<EOF
{
  "name": "$NAME",
  "vnc_port": $VNC_PORT,
  "cdp_port": $CDP_PORT,
  "vnc_url": "http://127.0.0.1:${VNC_PORT}/",
  "cdp_url": "http://127.0.0.1:${CDP_PORT}",
  "autoconnect_user_data_dir": "$SHIM_DIR",
  "profile_volume": "${PROFILE_VOL}",
  "start_url": "$START_URL",
  "proxy": "$PROXY",
  "created": "$(date -Is)"
}
EOF

cat <<EOF

[$NAME] 已就绪
  noVNC  (人工登录):  http://127.0.0.1:${VNC_PORT}/    [本机可直连]
  CDP    (逆向调试):  http://127.0.0.1:${CDP_PORT}
  autoConnect 目录:  $SHIM_DIR   (给 chrome-devtools-mcp --autoConnect --userDataDir 用)
  状态文件:          $STATE_FILE
  代理:              $PROXY

外部访问: ssh -N -L ${VNC_PORT}:127.0.0.1:${VNC_PORT} -L ${CDP_PORT}:127.0.0.1:${CDP_PORT} <你的主机>
EOF
