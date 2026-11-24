#!/usr/bin/env bash
# 关闭并清理 webtop-reverse 容器
# 用法: rev-down.sh [容器名|--all]
set -uo pipefail

STATE_DIR="${WEBTOP_REV_STATE:-${TMPDIR:-/tmp}/webtop-reverse}"

down_one() {
  local name="$1"
  local vf="$STATE_DIR/${name}.json"
  local vol="" acdir=""
  if [ -f "$vf" ]; then
    vol="$(python3 -c "import json;print(json.load(open('$vf')).get('profile_volume',''))" 2>/dev/null || true)"
    acdir="$(python3 -c "import json;print(json.load(open('$vf')).get('autoconnect_user_data_dir',''))" 2>/dev/null || true)"
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker rm -f "$name" >/dev/null 2>&1 && echo "[*] 已删除容器 $name"
  else
    echo "[*] 容器 $name 不存在"
  fi

  if [ -n "$vol" ]; then
    docker volume rm "$vol" >/dev/null 2>&1 && echo "[*] 已删除卷 $vol"
  fi

  # 状态文件可能已丢失，按约定路径兜底清理
  if [ -z "$acdir" ]; then
    acdir="$STATE_DIR/${name}-autoconnect"
  fi
  if [ -d "$acdir" ]; then
    rm -rf "$acdir" && echo "[*] 已删除 autoConnect 目录 $acdir"
  fi

  if [ -f "$vf" ]; then
    rm -f "$vf" && echo "[*] 已清理状态文件 $vf"
  fi
  return 0
}

if [ "${1:-}" = "--all" ]; then
  for n in $(docker ps -a --format '{{.Names}}' | grep -E '^rev-' || true); do down_one "$n"; done
  exit 0
fi

if [ -z "${1:-}" ]; then
  echo "用法: rev-down.sh <容器名|--all>" >&2
  exit 1
fi
down_one "$1"
