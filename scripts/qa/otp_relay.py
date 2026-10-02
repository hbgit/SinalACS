#!/usr/bin/env python3
"""Relé do código OTP do gateway `log` para o emulador (só desenvolvimento/e2e).

O gateway de log escreve o código no stdout do servidor; o emulador não lê
`docker logs`. Este servidor expõe só o código mais recente, sem destino nem CPF
(o log não os tem). Escuta em 127.0.0.1; o emulador chega por `adb reverse`.
"""
import json, os, re, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PADRAO = re.compile(r"\[SMS-GATEWAY=log\] código de acesso: (\d{6}) ")

def parse_latest_code(log_text):
    achados = PADRAO.findall(log_text)
    return achados[-1] if achados else None

def host_permitido(host, porta):
    """Só `localhost:<porta>` ou `127.0.0.1:<porta>`: um navegador com DNS rebinding
    chega aqui com o `Host` do site malicioso e é recusado."""
    return (host or "").lower() in (f"localhost:{porta}", f"127.0.0.1:{porta}")

# O relé se encerra sozinho: um runner morto por SIGKILL não deixa um leitor do
# `docker logs` da stack de desenvolvimento ocupando a porta.
VIDA_MAXIMA_S = 45 * 60

def count_codes(log_text):
    return len(PADRAO.findall(log_text))

def acs_do_manifesto(caminho):
    """Matrícula e senha sintéticas do ACS do manifesto de e2e, ou None.

    Só existe para o e2e de TELA do ACS. Opt-in: sem E2E_FIXTURES_FILE o relé
    não serve credencial nenhuma, e o e2e do paciente segue exatamente como era."""
    if not caminho:
        return None
    try:
        with open(caminho) as f:
            acs = json.load(f)["acs"]
        return {"matricula": acs["matricula"], "senha": acs["password"]}
    except (OSError, KeyError, ValueError):
        return None

class Handler(BaseHTTPRequestHandler):
    porta = 8765
    container = "sinalacs-serverpod"

    def do_GET(self):
        if not host_permitido(self.headers.get("Host"), self.porta):
            self.send_error(403); return
        url = urlparse(self.path)
        if url.path == "/now":
            # Relógio do host: o corte do código usa ESTE, não o do aparelho.
            self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
            self.wfile.write(str(int(time.time() * 1000)).encode())
            return
        if url.path == "/acs":
            credencial = acs_do_manifesto(os.environ.get("E2E_FIXTURES_FILE"))
            if credencial is None:
                self.send_error(404); return
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(json.dumps(credencial).encode())
            return
        if url.path not in ("/code", "/count"):
            self.send_error(404); return
        since_ms = int(parse_qs(url.query).get("since", ["0"])[0])
        desde = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(since_ms / 1000))
        saida = subprocess.run(["docker", "logs", "--since", desde, self.container],
                               capture_output=True, text=True)
        if url.path == "/count":
            # Quantos códigos foram emitidos depois de `since`: prova que um erro de
            # digitação não gastou outro pedido de SMS.
            self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
            self.wfile.write(str(count_codes(saida.stdout + saida.stderr)).encode())
            return
        code = parse_latest_code(saida.stdout + saida.stderr)
        if code is None:
            self.send_error(404); return
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
        self.wfile.write(code.encode())

    def log_message(self, *a):  # silencioso: o código não vai para o terminal
        pass

if __name__ == "__main__":
    import threading
    Handler.porta = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    servidor = HTTPServer(("127.0.0.1", Handler.porta), Handler)
    threading.Timer(VIDA_MAXIMA_S, servidor.shutdown).start()
    servidor.serve_forever()
