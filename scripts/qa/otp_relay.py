#!/usr/bin/env python3
"""Relé do código OTP do gateway `log` para o emulador (só desenvolvimento/e2e).

O gateway de log escreve o código no stdout do servidor; o emulador não lê
`docker logs`. Este servidor expõe só o código mais recente, sem destino nem CPF
(o log não os tem). Escuta em 127.0.0.1; o emulador chega por `adb reverse`.
"""
import re, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PADRAO = re.compile(r"\[SMS-GATEWAY=log\] código de acesso: (\d{6}) ")

def parse_latest_code(log_text):
    achados = PADRAO.findall(log_text)
    return achados[-1] if achados else None

class Handler(BaseHTTPRequestHandler):
    container = "sinalacs-serverpod"

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/now":
            # Relógio do host: o corte do código usa ESTE, não o do aparelho.
            self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
            self.wfile.write(str(int(time.time() * 1000)).encode())
            return
        if url.path != "/code":
            self.send_error(404); return
        since_ms = int(parse_qs(url.query).get("since", ["0"])[0])
        desde = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(since_ms / 1000))
        saida = subprocess.run(["docker", "logs", "--since", desde, self.container],
                               capture_output=True, text=True)
        code = parse_latest_code(saida.stdout + saida.stderr)
        if code is None:
            self.send_error(404); return
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
        self.wfile.write(code.encode())

    def log_message(self, *a):  # silencioso: o código não vai para o terminal
        pass

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), Handler).serve_forever()
