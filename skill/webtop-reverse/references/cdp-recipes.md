# CDP 常用片段

调试端点：`http://127.0.0.1:<cdp_port>`，WebSocket 根在 `/json/version` 的 `webSocketDebuggerUrl`。
所有 page 级命令要挂到具体 target 上，用 `/json` 里 `type=page` 的 `webSocketDebuggerUrl` 直接连更省事。

## 连上并求值

```python
import json, urllib.request, websocket

base = "http://127.0.0.1:<cdp_port>"
tabs = json.load(urllib.request.urlopen(base + "/json"))
tab = [t for t in tabs if t["type"] == "page"][0]
ws = websocket.create_connection(tab["webSocketDebuggerUrl"], suppress_origin=True)

ident = [0]
def send(method, params=None):
    ident[0] += 1
    ws.send(json.dumps({"id": ident[0], "method": method, "params": params or {}}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == ident[0]:
            return r

send("Page.enable")
print(send("Runtime.evaluate", {"expression": "document.title", "returnByValue": True}))
```

`suppress_origin=True` 很关键：Chromium 默认拒绝带 Origin 头的 WS 连接，容器里已用 `--remote-allow-origins=*` 放行，但客户端不发 Origin 更稳。

## 拿全部 cookie（含 HttpOnly）

```python
send("Network.enable")
r = send("Network.getAllCookies")
for c in r["result"]["cookies"]:
    print(c["name"], c["value"][:20], "httpOnly=", c.get("httpOnly"))
```

`document.cookie` 和 `cookieStore.getAll()` 都拿不到 HttpOnly，必须走 CDP。

## 记录网络请求

```python
send("Network.enable")
send("Network.setCacheDisabled", {"cacheDisabled": True})
# 之后监听 ws 消息里的 Network.requestWillBeSent / Network.responseReceived
```

回溯请求来源用 `Network.requestWillBeSent` 事件里的 `initiator` 字段（type 为 `script` 时含 `stackTrace`）。

## 注入 hook 采样

```python
send("Page.addScriptToEvaluateOnNewDocument", {"source": """
  window.__samples = [];
  const of = window.fetch;
  window.fetch = function(...a) {
    window.__samples.push({url: String(a[0]), body: a[1] && a[1].body});
    return of.apply(this, a);
  };
  const oo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, u, ...r) {
    window.__samples.push({method: m, url: u});
    return oo.call(this, m, u, ...r);
  };
"""})

# 之后读取
send("Runtime.evaluate", {"expression": "JSON.stringify(window.__samples)", "returnByValue": True})
```

## 截图确认画面

```python
r = send("Page.captureScreenshot", {"format": "png"})
open("shot.png", "wb").write(base64.b64decode(r["result"]["data"]))
```

容器里 Chromium 走 SwiftShader 软渲染，首次截图可能要几秒；超时的话调大等待时间。

## 打开新标签页

```python
send("Target.createTarget", {"url": "https://example.com"})
```

或直接用 `<repo>/scripts/cdp-open.py <cdp_base> <url>`。

## 注意

- 目标页面若在 iframe 里，`/json` 会多出 `type=iframe` 的条目，筛选时只取 `type=page`。
- 页面跳转后 target id 会变，重连前先刷新 `/json`。
- 容器内 Chromium 是 158.x，Selkies 桌面分辨率 1024x768（浏览器窗口 1920x1080）。
