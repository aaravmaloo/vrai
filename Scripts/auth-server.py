import argparse
import http.server
import signal
import sys


class AlwaysUnauthorized(http.server.BaseHTTPRequestHandler):
    server_version = "VraiAuthFixture/1.0"

    def answer(self):
        body = b"Credentials expired or revoked.\n"
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="vrai-fixture"')
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    do_GET = answer
    do_POST = answer
    do_HEAD = answer

    def log_message(self, fmt, *args):
        if self.server.verbose:
            sys.stderr.write("auth-server: " + (fmt % args) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Answer every request with 401 so the auth scenario fails like an expired token.")
    parser.add_argument("--port", type=int, default=47801)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), AlwaysUnauthorized)
    server.verbose = args.verbose
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print("auth-server: listening on http://127.0.0.1:%d" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
