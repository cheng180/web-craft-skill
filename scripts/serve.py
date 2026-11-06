#!/usr/bin/env python3
"""serve.py — 带 MIME 修正的静态服务器，用于镜像站本地对照。

比 `python -m http.server` 多做的三件事：
  1. 补 .webp/.avif/.mjs/.woff2 等 MIME（缺 MIME 时部分浏览器不渲染图片/字体）
  2. 无扩展名文件（镜像下来的 /api/xxx）按 JSON 返回，fetch().json() 才能解析
  3. --spa 时把未命中的路径 fallback 到 index.html（前端路由站点）

用法:
    python scripts/serve.py --root ./mirror --port 5174
    python scripts/serve.py --root ./mirror --port 5174 --spa
"""
import argparse
import http.server
import mimetypes
import os
import socketserver

EXTRA_TYPES = {
    ".webp": "image/webp",
    ".avif": "image/avif",
    ".mjs": "application/javascript",
    ".js": "application/javascript",
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
}

for ext, mime in EXTRA_TYPES.items():
    mimetypes.add_type(mime, ext)


class MirrorHandler(http.server.SimpleHTTPRequestHandler):
    spa = False

    def guess_type(self, path):
        base, ext = os.path.splitext(path)
        ext = ext.lower()
        if ext in EXTRA_TYPES:
            return EXTRA_TYPES[ext]
        if ext == "":
            # 无扩展名 = 镜像下来的 API 数据
            return "application/json"
        return super().guess_type(path)

    def send_head(self):
        try:
            return super().send_head()
        except (FileNotFoundError, NotADirectoryError):
            if self.spa:
                self.path = "/index.html"
                return super().send_head()
            raise

    def log_message(self, fmt, *args):
        # 只打印错误，避免刷屏
        if args and str(args[1]) not in ("200", "304"):
            super().log_message(fmt, *args)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="镜像目录")
    parser.add_argument("--port", type=int, default=5174)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--spa", action="store_true", help="未命中的路径 fallback 到 index.html")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        raise SystemExit(f"目录不存在: {root}")

    MirrorHandler.spa = args.spa
    handler = lambda *a, **kw: MirrorHandler(*a, directory=root, **kw)  # noqa: E731

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((args.bind, args.port), handler) as httpd:
        print(f"serving {root}")
        print(f"  -> http://{args.bind}:{args.port}/")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


if __name__ == "__main__":
    main()
