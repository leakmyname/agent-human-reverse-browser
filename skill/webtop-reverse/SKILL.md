---
name: webtop-reverse
description: 启动临时 webtop-reverse 容器，通过 noVNC 让人工登录目标网站，再用同一浏览器的 Chrome DevTools MCP 调试口做前端/API 逆向（抓请求、找签名、导出 cookie），逆向结束后销毁容器。适用于"给我一个网站，我登录后你逆向它的接口"这类需求。
---

# webtop-reverse：人工登录 + agent 逆向一体化容器

用户要逆向某个网站，但目标站点可能需要扫码、滑块或人机验证，纯无头浏览器过不去。
本方案起一个临时 webtop 容器：容器内 Chromium 带 CDP 调试口，**人通过 noVNC 看到的是真实浏览器画面并亲自登录**，agent 通过同一个 Chromium 实例的调试口观察同一份会话、拦截请求、分析签名。

人登录的会话和 agent 逆向的会话是同一个浏览器实例，所以登录态天然共享，不需要导出再导入 cookie。

## 前置

- 镜像已构建：`webtop-reverse:latest`（源码在 `<repo>/docker/`）
- 脚本在 `<repo>/scripts/`
- `chrome-devtools-mcp` 可用：`npx chrome-devtools-mcp@latest`
- 代理走宿主机 `7893`（脚本已默认注入容器环境变量）

镜像若不存在或被清理，先重建：

```bash
cd <repo>/docker && docker build -t webtop-reverse:latest .
```

## 工作流

### 1. 起容器

```bash
<repo>/scripts/rev-up.sh <容器名> <起始URL>
```

脚本会分配随机端口并打印：

- `noVNC (人工登录): http://127.0.0.1:<vnc_port>/`
- `CDP   (逆向调试): http://127.0.0.1:<cdp_port>`
- `autoConnect 目录: <state>/<容器名>-autoconnect`

如果用户不在本机，需要给隧道命令：`ssh -N -L <vnc_port>:127.0.0.1:<vnc_port> -L <cdp_port>:127.0.0.1:<cdp_port> <host>`。

### 2. 让用户登录

把 noVNC 地址给用户，明确说明：

- 在 noVNC 窗口里操作真实浏览器，登录目标站点
- 登录完成（进入已登录页面）后回复"好了"

**这一步必须等人。不要在用户未登录前开始逆向。**

### 3. 逆向（Chrome DevTools MCP）

这是本方案推荐的主通道，用官方 Chrome DevTools MCP 连进同一个浏览器。

**方式 A（推荐，官方 autoConnect 机制）**

MCP 按官方流程从 user-data-dir 里的 `DevToolsActivePort` 文件发现浏览器。
`rev-up.sh` 已经把该文件准备到宿主机目录 `<state>/<容器名>-autoconnect/`，直接用：

```bash
npx chrome-devtools-mcp@latest --autoConnect --userDataDir <state>/<容器名>-autoconnect
```

`rev-up.sh` 写进 `DevToolsActivePort` 的是**宿主机**的 CDP 端口，所以 MCP 在宿主机侧能直接连上。

**方式 B（直接指定 CDP 地址）**

更直白，端口是容器映射到宿主机的那个：

```bash
npx chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:<cdp_port>
```

两种方式都指向同一个浏览器实例，看到的是同一份登录态。

MCP 可用工具（v1.14 约 33 个）：

| 需求 | 工具 |
| --- | --- |
| 列出标签页 | `list_pages` / `select_page` |
| 抓网络请求 | `list_network_requests` / `get_network_request` |
| 读 DOM / 执行 JS | `take_snapshot` / `evaluate_script` |
| 截图 | `take_screenshot` |
| 控制台日志 | `list_console_messages` |
| 性能分析 | `performance_start_trace` / `performance_analyze_insight` |
| Lighthouse | `lighthouse_audit` |

**导出 cookie（含 HttpOnly）**：`document.cookie` 和 `cookieStore.getAll()` 都拿不到 HttpOnly。
必须走 CDP：`Network.enable` 后 `Network.getAllCookies`。片段见 `references/cdp-recipes.md`。

### 4. 收尾（必做）

逆向完成后销毁容器，释放内存和端口：

```bash
<repo>/scripts/rev-down.sh <容器名>
```

它会 `docker rm -f` + 删掉 profile 卷 + 删状态文件 + 删 autoConnect 目录。
确认没有遗留：

```bash
<repo>/scripts/rev-status.sh
```

用户中断任务时也要收尾。容器默认 `--restart=no`，不会自己复活，但容器和卷会一直占资源。

## 约束

- **不要用 kitesurf**：它是公共 playground，不能带私有 cookie。
- **不要用 `docker rm` 前先 `docker volume rm`**：profile 卷名由 `rev-up.sh` 生成并在状态文件里记录，交给 `rev-down.sh` 处理。
- 容器内存限制 1.5G、shm 1G，别调太大（本机总内存 7.7G 且已用约 6G）。
- 容器内 Chromium 用 `--no-sandbox`（容器 seccomp 限制），这是容器内常规做法。
- 调试口暴露了完整浏览器控制权，端口只绑 `127.0.0.1`，任务结束即销毁。
- **容器内无 GPU**，镜像已装 `chromium-angle` 提供 SwiftShader 软渲染。没有它页面合成层会是空白，用户在 noVNC 里看不到内容。

## 参考

- `references/cdp-recipes.md`：常用 CDP 调用片段（抓 cookie、注入 hook 采样、导出 HAR）
