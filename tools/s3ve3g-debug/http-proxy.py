#!/usr/bin/env python3
"""A minimal HTTP forward proxy (GET/HEAD with absolute URLs, and CONNECT) for the phone's apk.

The phone reaches it over the USB network through an SSH reverse tunnel, so package downloads use
this machine's internet connection instead of the phone's Wi-Fi:

    tools/s3ve3g-debug/http-proxy.py 3128 &
    ssh -R 3128:127.0.0.1:3128 jeff@172.16.42.1 \
        'sudo http_proxy=http://127.0.0.1:3128 https_proxy=http://127.0.0.1:3128 apk add ...'

Listens on 127.0.0.1 only.
"""
import select
import socket
import socketserver
import sys
import urllib.parse


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline(65536).decode("latin-1")
        if not line:
            return
        method, target, version = line.split()
        headers = []
        while True:
            h = self.rfile.readline(65536).decode("latin-1")
            if h in ("\r\n", "\n", ""):
                break
            headers.append(h)
        if method == "CONNECT":
            host, port = target.rsplit(":", 1)
            up = socket.create_connection((host, int(port)), timeout=30)
            self.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            self.pipe(up)
            return
        u = urllib.parse.urlsplit(target)
        up = socket.create_connection((u.hostname, u.port or 80), timeout=30)
        path = (u.path or "/") + ("?" + u.query if u.query else "")
        req = f"{method} {path} HTTP/1.0\r\n"
        for h in headers:
            k = h.split(":", 1)[0].strip().lower()
            if k not in ("proxy-connection", "connection", "keep-alive"):
                req += h
        req += "Connection: close\r\n\r\n"
        up.sendall(req.encode("latin-1"))
        self.pipe(up)

    def pipe(self, up):
        conns = [self.connection, up]
        try:
            while True:
                r, _, _ = select.select(conns, [], [], 120)
                if not r:
                    return
                for s in r:
                    data = s.recv(65536)
                    if not data:
                        return
                    (up if s is self.connection else self.connection).sendall(data)
        finally:
            up.close()


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3128
    Server(("127.0.0.1", port), Handler).serve_forever()
