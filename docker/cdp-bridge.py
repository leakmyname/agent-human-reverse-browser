#!/usr/bin/env python3
"""CDP 端口桥：把容器内 Chromium 的随机调试端口转发到固定端口 9223。

Chromium 用 --remote-debugging-port=0 启动，实际端口随机，并写进
user-data-dir/DevToolsActivePort（这也是 chrome-devtools-mcp --autoConnect
读取的同一个文件）。这个桥读取该文件，把 0.0.0.0:9223 转发过去，
这样宿主机 `docker -p` 映射的固定端口始终可用。

Chromium 的调试口只绑容器内 127.0.0.1，docker port 映射无法直连，必须走这个桥。
"""
import os
import socket
import threading
import time

LISTEN = ("0.0.0.0", 9223)
ACTIVE_PORT_FILE = os.environ.get(
    "CHROME_ACTIVE_PORT_FILE", "/config/chrome-profile/DevToolsActivePort"
)


def read_target_port():
    """读 DevToolsActivePort 首行，即 Chromium 实际调试端口。"""
    try:
        with open(ACTIVE_PORT_FILE) as fh:
            line = fh.readline().strip()
        return int(line)
    except (OSError, ValueError):
        return None


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client):
    port = read_target_port()
    if not port:
        client.close()
        return
    try:
        upstream = socket.create_connection(("127.0.0.1", port), timeout=5)
    except OSError:
        client.close()
        return
    client.settimeout(None)
    upstream.settimeout(None)
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()


def main():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(LISTEN)
    server.listen(64)
    print("cdp-bridge listening on %s:%d (target: DevToolsActivePort)" % LISTEN, flush=True)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
