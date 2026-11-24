#!/usr/bin/env bash
# 关闭并清理 webtop-reverse 容器
# 用法: rev-down.sh [容器名|--all]
set -uo pipefail

STATE_DIR="${WEBTOP_REV_STATE:-${TMPDIR:-/tmp}/webtop-reverse}"

down_one() {
  local name="$1"
  local vf="$STATE_DIR/${name}.json"
  local vol=""
  [ -f "$vf" ] && vol="$(python3 -c "import json,sys;print(json.load(open('$vf')).get('profile_volume',''))" 2>/dev/null || true)"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker rm -f "$name" >/dev/null 2>&1 && echo "[*] 已删除容器 $name"
  else
    echo "[*] 容器 $name 不存在"
  fi
  if [ -n "$vol" ]; then
    docker volume rm "$vol" >/dev/null 2>&1 && echo "[*] 已删除卷 $vol"
  fi
  [ -f "$vf" ] && rm -f "$vf" && echo "[*] 已清理状态文件 $vf"
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
