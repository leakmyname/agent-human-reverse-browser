# agent-human-reverse-browser

**人负责登录，agent 负责逆向。**

起一个临时 webtop 容器：容器里的 Chromium 带 CDP 调试口，你通过 noVNC 看到的是真实浏览器画面并亲自完成登录；
agent 通过**同一个** Chromium 实例的调试口观察同一份会话、抓请求、分析签名、导出 cookie。
登录态天然共享，不需要导出再导入。

适合目标站点有扫码、滑块、人机验证，纯无头浏览器过不去的场景。

---

## 它是怎么工作的

```
┌────────────────────────── 你的电脑 ──────────────────────────┐
│  浏览器打开 noVNC，看到容器桌面，手动登录                        │
└───────────────────────────┬──────────────────────────────────┘
                            │ HTTP/WebSocket (noVNC)
┌───────────────────────────▼──────────────────────────────────┐
│  Docker 容器 webtop-reverse                                   │
│                                                              │
│   KasmVNC/Xvnc :1 ──► openbox ──► Chromium                    │
│                        │              │                       │
│                        │              └─ :9222 (CDP, 仅本地)   │
│                        │                     │                 │
│                        │              cdp-bridge.py           │
│                        │                     │                 │
│                        └──────────── :3000/:3001 (noVNC)  :9223│
└──────────────────────────────────────────────────────────────┘
                                              ▲
                                              │ CDP (WebSocket)
                                     ┌────────┴─────────┐
                                     │  agent 逆向分析   │
                                     └──────────────────┘
```

- 基于 `lscr.io/linuxserver/webtop:alpine-openbox`，自带 KasmVNC + Chromium
- Chromium 启动参数已包含 `--remote-debugging-port=9222 --remote-allow-origins=*`
- Chromium 的调试口只监听 `127.0.0.1`，由容器内 `cdp-bridge.py` 转发到 `0.0.0.0:9223`，`docker -p` 才能映射出来
- 端口只绑定宿主机 `127.0.0.1`，外部访问走 SSH 隧道

---

## 快速开始

### 1. 构建镜像

```bash
git clone git@github.com:leakmyname/agent-human-reverse-browser.git
cd agent-human-reverse-browser
docker build -t webtop-reverse:latest docker/
```

镜像约 1.8G（基于已缓存的 webtop 基础镜像时构建只需几秒）。

### 2. 起一个临时容器

```bash
./scripts/rev-up.sh <容器名> <起始URL>
```

例如：

```bash
./scripts/rev-up.sh rev-shop https://example.com/login
```

脚本会：

- 分配两个随机空闲端口（noVNC 和 CDP）
- 启动容器，内存限制 1.5G，`--restart=no`
- 等待 CDP 就绪
- 通过 CDP 打开起始 URL
- 写状态文件到 `${WEBTOP_REV_STATE:-${TMPDIR:-/tmp}/webtop-reverse}/<容器名>.json`

输出示例：

```
[rev-shop] 已就绪
  noVNC  (人工登录):  http://127.0.0.1:46843/
  CDP    (逆向调试):  http://127.0.0.1:53889
  状态文件:          /tmp/webtop-reverse/rev-shop.json
  代理:              http://172.17.0.1:7893

外部访问: ssh -N -L 46843:127.0.0.1:46843 -L 53889:127.0.0.1:53889 <你的主机>
```

### 3. 登录（人）

在浏览器里打开 noVNC 地址，像用正常浏览器一样登录目标站点。完成并进入已登录页面后，告诉 agent"好了"。

### 4. 逆向（agent）

CDP 端点 `http://127.0.0.1:<cdp_port>` 已可用。常用操作：

```bash
# 在容器浏览器里打开新页面
./scripts/cdp-open.py http://127.0.0.1:<cdp_port> <url>
```

agent 侧可用的能力：

| 能力 | CDP 方法 |
| --- | --- |
| 查看当前所有标签页 | `GET /json` |
| 执行 JS / 读 DOM | `Runtime.evaluate` |
| 抓网络请求 | `Network.enable` + 事件流 |
| 回溯请求来源 | `Network.requestWillBeSent` 的 `initiator` |
| 导出全部 cookie（含 HttpOnly） | `Network.getAllCookies` |
| 注入 hook 采样 | `Page.addScriptToEvaluateOnNewDocument` |
| 截图 | `Page.captureScreenshot` |

细节见 [`skill/webtop-reverse/references/cdp-recipes.md`](skill/webtop-reverse/references/cdp-recipes.md)。

### 5. 收尾

```bash
./scripts/rev-down.sh <容器名>
```

删除容器、profile 卷和状态文件。查看所有实例：

```bash
./scripts/rev-status.sh
```

---

## 作为 Codex skill 使用

把 `skill/webtop-reverse/` 整个目录复制到 skills 目录即可：

```bash
cp -r skill/webtop-reverse ~/.codex/skills/
```

之后 agent 看到"我登录了，你逆向这个站点的接口"这类需求时，会按 skill 里的流程起容器、等你登录、再用 CDP 分析、最后销毁容器。

---

## 已知问题与设计决策

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| CDP WebSocket 握手 403 | Chromium 默认拒绝带 Origin 头的连接 | `--remote-allow-origins=*` |
| 宿主机连不上 9222 | Chromium 调试口只绑容器内 `127.0.0.1` | `cdp-bridge.py` 转发到 `0.0.0.0:9223` |
| Chromium 起不来，日志报 `SingletonLock` 权限错误 | profile 目录属主不是容器内 `abc` 用户 | 镜像构建时预建并 `chown abc:abc` |
| Chromium 日志写不进 `/tmp` | 容器内 `/tmp` 已被 root 占用 | 日志改写到 `/config/logs` |
| 容器内访问宿主代理连接被拒 | 容器内 `127.0.0.1` 是容器自己 | 用 docker0 网桥地址（`172.17.0.1`） |

### 资源占用

- 容器内存限制 `1.5G`，`--shm-size=1g`
- 基础镜像 + 运行时约 300–600MB 常驻
- `--restart=no`，容器不会自我复活，但不会自动消失——**用完必须 `rev-down.sh`**

---

## 安全提示

调试口等于完整的浏览器控制权：可以读所有 cookie、执行任意页面脚本、代表你操作已登录的账号。

- 端口只绑 `127.0.0.1`，不要改成 `0.0.0.0` 暴露到公网
- 不要把 CDP 端口或 noVNC 端口转发给不可信的人
- 任务结束立即销毁容器（`rev-down.sh`），profile 卷会一并删除
- 需要保留登录态复用时可改用宿主目录挂载 profile 卷，但要注意这相当于把 cookie 明文落盘

---

## 目录结构

```
docker/                        镜像源码
  Dockerfile
  cdp-bridge.py                CDP 端口转发（127.0.0.1:9222 → 0.0.0.0:9223）
  start-browser.sh             启动 Chromium + CDP 桥
scripts/
  rev-up.sh                    起容器，分配随机端口，输出 noVNC/CDP 地址
  rev-down.sh                  销毁容器 + 卷 + 状态文件
  rev-status.sh                列出所有实例状态
  cdp-open.py                  通过 CDP 在容器浏览器里打开 URL
skill/
  webtop-reverse/
    SKILL.md                   Codex skill 主文件
    references/cdp-recipes.md  常用 CDP 调用片段
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `WEBTOP_REV_IMAGE` | `webtop-reverse:latest` | 使用的镜像 |
| `WEBTOP_REV_STATE` | `${TMPDIR:-/tmp}/webtop-reverse` | 状态文件目录 |
| `WEBTOP_REV_PROXY` | `http://172.17.0.1:7893` | 容器内使用的 HTTP 代理 |

不用代理的话：`WEBTOP_REV_PROXY= ./scripts/rev-up.sh ...`（空值会写入空代理变量）。

---

## 依赖

- Docker（含 `docker run` / `docker volume` 权限）
- Python 3 + `websocket-client`（`pip install websocket-client`，仅 `cdp-open.py` 需要）
- `curl`（`rev-up.sh` 探测 CDP 就绪）
