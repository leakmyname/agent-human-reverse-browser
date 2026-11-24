#!/usr/bin/env python3
"""TCP 转发：0.0.0.0:9223 -> 127.0.0.1:9222 (Chromium DevTools)。

Chromium 的 --remote-debugging-address 只会绑 127.0.0.1，docker port 映射无法直连，
所以在容器内用这个极简桥把 CDP 暴露到 0.0.0.0。
"""
import socket
import threading

LISTEN = ("0.0.0.0", 9223)
TARGET = ("127.0.0.1", 9222)


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
    try:
        upstream = socket.create_connection(TARGET, timeout=5)
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
    print("cdp-bridge listening on %s:%d -> %s:%d" % (LISTEN[0], LISTEN[1], TARGET[0], TARGET[1]), flush=True)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
