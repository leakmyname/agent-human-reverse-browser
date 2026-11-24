#!/usr/bin/env python3
"""通过 CDP 在容器浏览器里打开 URL。用法: cdp-open.py <cdp_base_url> <url>"""
import json, sys, urllib.request, websocket

def main():
    base, url = sys.argv[1], sys.argv[2]
    ver = json.load(urllib.request.urlopen(base + "/json/version"))
    ws = websocket.create_connection(ver["webSocketDebuggerUrl"], suppress_origin=True)
    ident = [0]
    def send(method, params=None):
        ident[0] += 1
        ws.send(json.dumps({"id": ident[0], "method": method, "params": params or {}}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == ident[0]:
                return msg
    send("Target.createTarget", {"url": url})
    print("opened:", url)

if __name__ == "__main__":
    main()
