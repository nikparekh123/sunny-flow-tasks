"""The gate in front of Theta Terminal.

Every request must carry `x-proxy-key` equal to the PROXY_KEY secret, or it
gets a 401 and never reaches the Terminal. GET only. /healthz answers without
a key and says whether the Terminal is listening, so Fly can restart it.
"""
import hmac, os, socket, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = os.environ.get("PROXY_KEY", "")
UP = os.environ.get("THETA_UPSTREAM", "http://127.0.0.1:25503")

def terminal_up() -> bool:
    try:
        with socket.create_connection(("127.0.0.1", int(UP.rsplit(":", 1)[1])), timeout=2):
            return True
    except OSError:
        return False

class Gate(BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200 if terminal_up() else 503, b"ok" if terminal_up() else b"terminal down")
        got = self.headers.get("x-proxy-key", "")
        if not KEY or not hmac.compare_digest(got, KEY):
            return self._send(401, b"unauthorized")
        try:
            with urllib.request.urlopen(UP + self.path, timeout=60) as r:
                return self._send(r.status, r.read(), r.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as e:
            return self._send(e.code, e.read(), e.headers.get("Content-Type", "text/plain"))
        except Exception as e:  # Terminal not up yet, or it hung
            return self._send(502, str(e).encode())

    def log_message(self, *a):  # keep keys and queries out of the logs
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Gate).serve_forever()
