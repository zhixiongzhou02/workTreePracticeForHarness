#!/usr/bin/env python3

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


def runtime_payload() -> dict:
    return {
        "worktreeId": os.environ.get("WORKTREE_ID", ""),
        "appPort": os.environ.get("APP_PORT", ""),
        "apiPort": os.environ.get("API_PORT", ""),
        "appUrl": os.environ.get("APP_URL", ""),
        "stateRoot": os.environ.get("STATE_ROOT", ""),
        "logRoot": os.environ.get("LOG_ROOT", ""),
        "artifactRoot": os.environ.get("ARTIFACT_ROOT", ""),
    }


class Handler(BaseHTTPRequestHandler):
    # 示例应用只需要一个稳定的健康检查和运行态查看接口。
    def do_GET(self) -> None:
        if self.path not in {"/", "/healthz"}:
            self.send_response(404)
            self.end_headers()
            return

        body = json.dumps(runtime_payload(), ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args) -> None:
        log_root = os.environ.get("LOG_ROOT")
        if not log_root:
            return

        os.makedirs(log_root, exist_ok=True)
        message = "%s - - [%s] %s\n" % (
            self.address_string(),
            self.log_date_time_string(),
            format % args,
        )
        with open(os.path.join(log_root, "example-server-access.log"), "a", encoding="utf-8") as fh:
            fh.write(message)


def main() -> None:
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ["APP_PORT"])
    server = HTTPServer((host, port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
