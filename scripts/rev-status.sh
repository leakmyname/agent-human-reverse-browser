#!/usr/bin/env bash
# 查看 webtop-reverse 容器状态与端口
set -uo pipefail
STATE_DIR="${WEBTOP_REV_STATE:-${TMPDIR:-/tmp}/webtop-reverse}"
for f in "$STATE_DIR"/*.json; do
  [ -e "$f" ] || continue
  python3 - "$f" <<'PY'
import json,sys,subprocess
s=json.load(open(sys.argv[1]))
name=s["name"]
alive=subprocess.run(["docker","ps","--format","{{.Names}}"],capture_output=True,text=True).stdout.split()
state="运行中" if name in alive else "已停止"
print(f'[{name}] {state}  vnc={s["vnc_url"]}  cdp={s["cdp_url"]}')
PY
done
