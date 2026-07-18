#!/usr/bin/env python3
"""build/web 를 COOP/COEP 헤더와 함께 서빙 (Godot 웹 호환).
스레드 미사용 빌드라도 있으면 안전. 폰에서 같은 와이파이로 접속해 테스트.
실행: python3 tools/serve_web.py  → http://localhost:8060
"""
import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", "8060"))
ROOT = os.path.join(os.path.dirname(__file__), "..", "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.abspath(ROOT), **kwargs)


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


if not os.path.isdir(ROOT):
    raise SystemExit("build/web 없음 — 먼저 tools/export_web.sh 실행")

with ReusableTCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print("서빙: http://localhost:%d  (폰: http://<맥IP>:%d)" % (PORT, PORT))
    httpd.serve_forever()
