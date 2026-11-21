#!/usr/bin/env python3
"""bws-broker: runs a narrow subset of `bws` on behalf of the devcontainer.

The Bitwarden Secrets Manager access token lives only in this container. The
devcontainer's `bws` client POSTs {"argv": [...]} to /bws and gets back
{"exit": n, "stdout": "...", "stderr": "..."}.

Allowed commands (each with -o/--output json|tsv|none, default json):

  bws --version
  bws project list
  bws secret list [PROJECT_ID]
  bws secret create [--note NOTE] [--] KEY VALUE PROJECT_ID
  bws secret edit [--key K] [--value V] [--note N] [--project-id P] [--] SECRET_ID

Secret values are removed from every response, so a client can write
secrets but never read one back. Everything else (secret get, delete, run,
--server-url, --access-token, ...) is refused. The broker builds the bws
command line itself, so client input never becomes a bws flag.

Set BWS_BROKER_ALLOW_EDIT=0 to also refuse `secret edit` (overwriting an
existing secret).

https://:8006/api2/json/... (optional, enabled by BWS_BROKER_PVE_URL) proxies the
Proxmox VE API for OpenTofu. The broker reads the API token from Bitwarden
itself (secret BWS_BROKER_PVE_TOKEN_SECRET_ID, fixed by config, never chosen
by the client), sets the Authorization header, and forwards to Proxmox over
TLS pinned to BWS_BROKER_PVE_FINGERPRINT. The token never leaves the broker.
Only version/cluster/nodes paths are forwarded, minus console, shell, guest
exec and batch endpoints; /access (users, tokens, ACLs) is refused.
"""

import errno
import hashlib
import http.client
import json
import os
import re
import ssl
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

LISTEN_HOST = os.environ.get("BWS_BROKER_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("BWS_BROKER_PORT", "8080"))
TOKEN_FILE = os.environ.get("BWS_BROKER_TOKEN_FILE", "/run/secrets/bws_access_token")
BWS_BIN = os.environ.get("BWS_BROKER_BWS", "bws")
ALLOW_EDIT = os.environ.get("BWS_BROKER_ALLOW_EDIT", "1") == "1"
MAX_BODY = 64 * 1024
BWS_TIMEOUT = 60

OUTPUTS = {"json", "tsv", "none"}

# Proxmox API proxy (TLS listener on PVE_PORT). Disabled unless BWS_BROKER_PVE_URL is set.
PVE_URL = os.environ.get("BWS_BROKER_PVE_URL", "").rstrip("/")
PVE_TOKEN_SECRET_ID = os.environ.get("BWS_BROKER_PVE_TOKEN_SECRET_ID", "")
PVE_FINGERPRINT = os.environ.get("BWS_BROKER_PVE_FINGERPRINT", "").replace(":", "").lower()
PVE_PORT = int(os.environ.get("BWS_BROKER_PVE_PORT", "8006"))
PVE_PREFIX = "/api2/json/"
PVE_METHODS = {"GET", "POST", "PUT", "DELETE"}
PVE_MAX_BODY = 1024 * 1024
PVE_TIMEOUT = 120
# Re-read the token from Bitwarden this often, so a rotation is picked up
# without restarting the broker (a 401 from Proxmox also forces a re-read)
PVE_TOKEN_TTL = 300
# Top-level API paths the proxy forwards (all that bpg/proxmox needs here).
# PVE_ALLOW_READ is GET only: bpg lists pools for every VM, and reads a
# storage definition (GET /storage/<id>) before uploading a snippet or image.
# The storage listing (GET /storage) is allowed too. Proxmox leaves stored
# passwords and keys out of both. /access (users, tokens, ACLs) and any
# /storage write are refused.
PVE_ALLOW = re.compile(r"^(version|cluster|nodes)(/|$)")
PVE_ALLOW_READ = re.compile(r"^(pools(/|$)|storage(/[^/]+)?$)")
# Refused even under an allowed prefix: consoles and shells, migration
# tunnels, the batch API (it would bypass these rules) and guest agent
# commands that run code or touch files inside a VM.
PVE_DENY = [
    re.compile(p, re.IGNORECASE)
    for p in (
        r"(^|/)(termproxy|vncproxy|vncwebsocket|vncshell|spiceproxy|spiceshell|mtunnel|mtunnelwebsocket)$",
        r"^nodes/[^/]+/execute$",
        r"^nodes/[^/]+/(qemu|lxc)/[^/]+/agent/(exec|exec-status|file-read|file-write|set-user-password)$",
    )
]
PVE_TOKEN_RE = re.compile(r"^[^@\s]+@[^!\s]+![^=\s]+=[0-9a-fA-F-]{36}$")
PVE_FORWARD_HEADERS = ("Content-Type", "Accept")

# (group, action) -> allowed flags and (min, max) positional args
COMMANDS = {
    ("project", "list"): {"flags": set(), "pos": (0, 0)},
    ("secret", "list"): {"flags": set(), "pos": (0, 1)},
    ("secret", "create"): {"flags": {"--note"}, "pos": (3, 3)},
}
if ALLOW_EDIT:
    COMMANDS[("secret", "edit")] = {
        "flags": {"--key", "--value", "--note", "--project-id"},
        "pos": (1, 1),
    }

# tsv columns: the same as bws, minus the secret value
TSV_COLUMNS = {
    "project": [("ID", "id"), ("Name", "name"), ("Creation Date", "creationDate"), ("Revision Date", "revisionDate")],
    "secret": [("ID", "id"), ("Key", "key"), ("Creation Date", "creationDate"), ("Revision Date", "revisionDate")],
}


class Refused(Exception):
    pass


def load_token():
    try:
        with open(TOKEN_FILE, encoding="utf-8") as f:
            token = f.read().strip()
    except OSError as e:
        sys.exit(f"bws-broker: cannot read access token from {TOKEN_FILE}: {e.strerror}")
    if not token:
        sys.exit(f"bws-broker: access token file {TOKEN_FILE} is empty")
    return token


TOKEN = load_token()
# bws tokens look like 0.<id>.<client secret>:<encryption key>; scrub each
# part as well as the whole thing from anything sent back
SCRUB = sorted({TOKEN, *TOKEN.replace(":", ".").split(".")} - {"", "0"}, key=len, reverse=True)
SCRUB = [s for s in SCRUB if len(s) >= 8]


def scrub(text):
    for s in SCRUB + pve_scrub_list():
        text = text.replace(s, "[redacted]")
    return text


def parse(argv):
    """Turn client argv into (group, action, output, flags, positionals)."""
    if len(argv) < 2:
        raise Refused("usage: bws project list | secret list|create|edit ...")
    group, action, rest = argv[0], argv[1], argv[2:]
    spec = COMMANDS.get((group, action))
    if spec is None:
        raise Refused(f"'{group} {action}' is not allowed through the broker")

    flags, pos, output = {}, [], "json"
    i, end_of_opts = 0, False
    while i < len(rest):
        arg = rest[i]
        if end_of_opts or not arg.startswith("-") or arg == "-":
            pos.append(arg)
        elif arg == "--":
            end_of_opts = True
        else:
            name, eq, value = arg.partition("=")
            if name == "-o":
                name = "--output"
            if name != "--output" and name not in spec["flags"]:
                raise Refused(f"flag '{name}' is not allowed for '{group} {action}'")
            if not eq:
                i += 1
                if i >= len(rest):
                    raise Refused(f"{name} needs a value")
                value = rest[i]
            if name == "--output":
                output = value
            else:
                flags[name] = value
        i += 1

    if output not in OUTPUTS:
        raise Refused(f"output '{output}' is not supported (json, tsv, none)")
    lo, hi = spec["pos"]
    if not lo <= len(pos) <= hi:
        raise Refused(f"'{group} {action}' takes {lo}-{hi} positional arguments, got {len(pos)}")
    return group, action, output, flags, pos


def build_bws_args(group, action, flags, pos):
    args = [group, action, "--output", "json"]
    args += [f"{name}={value}" for name, value in flags.items()]
    if pos:
        args += ["--", *pos]
    return args


def strip_values(data):
    if isinstance(data, list):
        return [strip_values(d) for d in data]
    if isinstance(data, dict):
        return {k: v for k, v in data.items() if k != "value"}
    return data


def render(group, output, data):
    if output == "none":
        return ""
    if output == "json":
        return json.dumps(data, indent=2) + "\n"
    rows = data if isinstance(data, list) else [data]
    cols = TSV_COLUMNS[group]
    lines = ["\t".join(h for h, _ in cols)]
    lines += ["\t".join(str(row.get(k, "")) for _, k in cols) for row in rows]
    return "\n".join(lines) + "\n"


def run_bws(args):
    env = {
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "BWS_ACCESS_TOKEN": TOKEN,
    }
    return subprocess.run(
        [BWS_BIN, *args],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=BWS_TIMEOUT,
    )


def describe(group, action, flags, pos):
    """Log line for an allowed request: key names and IDs only, never values."""
    if action == "create":
        return f"{group} {action} key={pos[0]!r} project={pos[2]}"
    if action == "edit":
        changed = ",".join(sorted(f.lstrip("-") for f in flags)) or "nothing"
        return f"{group} {action} id={pos[0]} fields={changed}"
    return f"{group} {action} {' '.join(pos)}".rstrip()


def handle(argv):
    if argv in (["--version"], ["-V"]):
        proc = run_bws(["--version"])
        return {"exit": proc.returncode, "stdout": scrub(proc.stdout), "stderr": scrub(proc.stderr)}

    group, action, output, flags, pos = parse(argv)
    log(describe(group, action, flags, pos))
    proc = run_bws(build_bws_args(group, action, flags, pos))
    if proc.returncode != 0:
        # bws errors don't echo values, but scrub the token just in case
        return {"exit": proc.returncode, "stdout": "", "stderr": scrub(proc.stderr)}
    try:
        data = strip_values(json.loads(proc.stdout)) if proc.stdout.strip() else []
    except json.JSONDecodeError:
        return {"exit": 1, "stdout": "", "stderr": "bws-broker: bws returned output that is not JSON\n"}
    return {"exit": 0, "stdout": render(group, output, data), "stderr": scrub(proc.stderr)}


def log(msg):
    print(f"bws-broker: {msg}", flush=True)


# ---------------------------------------------------------------------------
# Proxmox API proxy (https://bws-broker:8006/api2/json/...)
# ---------------------------------------------------------------------------
class PveError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


_pve_lock = threading.Lock()
_pve_token = None
_pve_fetched = 0.0


def pve_check_config():
    if not PVE_URL:
        return
    u = urlsplit(PVE_URL)
    if u.scheme != "https" or not u.hostname:
        sys.exit(f"bws-broker: BWS_BROKER_PVE_URL must be https://host[:port], got {PVE_URL!r}")
    if not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", PVE_TOKEN_SECRET_ID):
        sys.exit("bws-broker: BWS_BROKER_PVE_TOKEN_SECRET_ID must be a Bitwarden secret UUID")
    if not re.fullmatch(r"[0-9a-f]{64}", PVE_FINGERPRINT):
        sys.exit("bws-broker: BWS_BROKER_PVE_FINGERPRINT must be the SHA-256 fingerprint of the Proxmox API cert")


def pve_token(refresh=False):
    """The Proxmox API token, read from Bitwarden and cached for PVE_TOKEN_TTL."""
    global _pve_token, _pve_fetched
    with _pve_lock:
        if refresh or _pve_token is None or time.monotonic() - _pve_fetched > PVE_TOKEN_TTL:
            proc = run_bws(["secret", "get", "--output", "json", "--", PVE_TOKEN_SECRET_ID])
            if proc.returncode != 0:
                log(f"pve: reading the token from Bitwarden failed: {scrub(proc.stderr).strip()}")
                raise PveError(502, "bws-broker: could not read the Proxmox token from Bitwarden")
            try:
                value = json.loads(proc.stdout)["value"].strip()
            except (ValueError, KeyError, TypeError, AttributeError):
                raise PveError(502, "bws-broker: Bitwarden returned an unexpected secret format")
            value = value.removeprefix("PVEAPIToken=")
            if not PVE_TOKEN_RE.fullmatch(value):
                raise PveError(502, "bws-broker: the Proxmox token secret is not user@realm!tokenid=uuid")
            _pve_token, _pve_fetched = value, time.monotonic()
        return _pve_token


def pve_scrub_list():
    token = _pve_token
    if not token:
        return []
    return [token, token.rpartition("=")[2]]


def pve_route(method, raw_path):
    """Check a client request; return (upstream path, path for logs)."""
    path, _, query = raw_path.partition("?")
    if not path.startswith(PVE_PREFIX):
        raise PveError(404, "bws-broker: only /api2/json/... is proxied")
    rest = path[len(PVE_PREFIX):]
    # Check the decoded form: Proxmox decodes %2F etc. before routing
    decoded = unquote(rest)
    segments = decoded.split("/")
    if any(s in (".", "..") for s in segments) or "//" in decoded or "\x00" in decoded:
        raise PveError(400, "bws-broker: path not allowed")
    allowed = PVE_ALLOW.match(decoded) or (method == "GET" and PVE_ALLOW_READ.match(decoded))
    if not allowed or any(p.search(decoded) for p in PVE_DENY):
        raise PveError(403, f"bws-broker: {method} /api2/json/{decoded} is not allowed through the broker")
    upstream = "/api2/json/" + rest + (f"?{query}" if query else "")
    return upstream, f"/{decoded}"


def pve_connect():
    u = urlsplit(PVE_URL)
    # Proxmox uses a self-signed cert: skip CA checks, pin the fingerprint instead
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    conn = http.client.HTTPSConnection(u.hostname, u.port or 8006, context=ctx, timeout=PVE_TIMEOUT)
    try:
        conn.connect()
        der = conn.sock.getpeercert(binary_form=True)
    except OSError as e:
        conn.close()
        raise PveError(502, f"bws-broker: cannot reach Proxmox: {e}")
    if hashlib.sha256(der).hexdigest() != PVE_FINGERPRINT:
        conn.close()
        log("pve: Proxmox certificate does not match BWS_BROKER_PVE_FINGERPRINT; refusing")
        raise PveError(502, "bws-broker: Proxmox certificate fingerprint mismatch")
    return conn


def pve_forward(method, upstream, headers, body):
    """Send one request to Proxmox; return (status, reason, content type, body)."""
    for attempt in (1, 2):
        token = pve_token(refresh=attempt == 2)
        conn = pve_connect()
        try:
            conn.request(method, upstream, body=body, headers={**headers, "Authorization": f"PVEAPIToken={token}"})
            resp = conn.getresponse()
            data = resp.read()
        except (OSError, http.client.HTTPException) as e:
            raise PveError(502, f"bws-broker: Proxmox request failed: {e}")
        finally:
            conn.close()
        # A 401 may mean the token was rotated in Bitwarden: re-read it once
        if resp.status != 401:
            break
    return resp.status, resp.reason, resp.getheader("Content-Type", "application/json"), data


class JsonHandler(BaseHTTPRequestHandler):
    server_version = "bws-broker"
    sys_version = ""

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        # requests are logged by the handlers; the default line adds nothing useful
        pass


class Handler(JsonHandler):
    """Plain HTTP listener: /bws and /healthz."""

    def do_GET(self):
        if self.path == "/healthz":
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/bws":
            self.send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if not 0 < length <= MAX_BODY:
            self.send_json(413, {"error": "body missing or too large"})
            return
        try:
            argv = json.loads(self.rfile.read(length))["argv"]
            if not isinstance(argv, list) or not all(isinstance(a, str) for a in argv):
                raise ValueError
        except (ValueError, KeyError, TypeError):
            self.send_json(400, {"error": 'expected {"argv": ["...", ...]}'})
            return
        try:
            result = handle(argv)
        except Refused as e:
            log(f"refused: {e}")
            result = {"exit": 2, "stdout": "", "stderr": f"bws-broker: refused: {e}\n"}
        except subprocess.TimeoutExpired:
            result = {"exit": 1, "stdout": "", "stderr": "bws-broker: bws timed out\n"}
        self.send_json(200, result)


class PveHandler(JsonHandler):
    """TLS listener: /api2/json/* proxied to Proxmox."""

    def do_GET(self):
        self.proxy()

    do_POST = do_PUT = do_DELETE = do_GET

    def proxy(self):
        method = self.command
        try:
            if method not in PVE_METHODS:
                raise PveError(405, f"bws-broker: {method} is not allowed")
            upstream, shown = pve_route(method, self.path)
            if "Transfer-Encoding" in self.headers:
                raise PveError(411, "bws-broker: send Content-Length, not chunked bodies")
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1
            if not 0 <= length <= PVE_MAX_BODY:
                raise PveError(413, "bws-broker: body too large")
            body = self.rfile.read(length) if length else None
            # Only these client headers pass through: never Authorization,
            # Cookie or CSRFPreventionToken
            headers = {h: self.headers[h] for h in PVE_FORWARD_HEADERS if self.headers.get(h)}
            status, reason, ctype, data = pve_forward(method, upstream, headers, body)
        except PveError as e:
            log(f"pve {method} {self.path.partition('?')[0]} refused: {e}")
            self.send_json(e.status, {"data": None, "errors": {"broker": str(e)}})
            return
        log(f"pve {method} {shown} -> {status}")
        for s in pve_scrub_list():
            data = data.replace(s.encode(), b"[redacted]")
        self.send_response(status, scrub(reason or ""))
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def bind(port, handler, what, env_var):
    """Create a listening server, or exit with a readable reason if the bind fails."""
    try:
        return ThreadingHTTPServer((LISTEN_HOST, port), handler)
    except OSError as e:
        hints = {
            errno.EADDRINUSE: f"another process is already listening on port {port}; "
                              f"stop it or set {env_var} to a free port",
            errno.EACCES: "ports below 1024 need root or CAP_NET_BIND_SERVICE; "
                          f"or set {env_var} to a port >= 1024",
            errno.EADDRNOTAVAIL: f"{LISTEN_HOST!r} is not an address of this container; check BWS_BROKER_HOST",
        }
        hint = hints.get(e.errno)
        sys.exit(f"bws-broker: cannot listen on {LISTEN_HOST}:{port} for {what}: {e.strerror or e}"
                 + (f" ({hint})" if hint else ""))


def pve_listener():
    """TLS server for the proxy, with a self-signed cert made at startup.

    bpg/proxmox only accepts an https endpoint and always calls /api2/json/
    on its host (a path prefix is dropped), hence a separate port. The cert
    lives in /tmp (tmpfs) and is new on every start; OpenTofu's provider runs
    with insecure = true, and only a placeholder token crosses this hop.
    """
    cert, key = "/tmp/pve-proxy.crt", "/tmp/pve-proxy.key"
    proc = subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
         "-days", "3650", "-subj", "/CN=bws-broker",
         "-addext", "subjectAltName=DNS:bws-broker,DNS:localhost,IP:127.0.0.1",
         "-keyout", key, "-out", cert],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"bws-broker: generating the /api2 TLS cert failed: {proc.stderr.strip()}")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(cert, key)
    server = bind(PVE_PORT, PveHandler, "the Proxmox API proxy", "BWS_BROKER_PVE_PORT")
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    return server


def main():
    pve_check_config()
    server = bind(LISTEN_PORT, Handler, "the bws endpoint", "BWS_BROKER_PORT")
    log(f"listening on {LISTEN_HOST}:{LISTEN_PORT} (secret edit {'allowed' if ALLOW_EDIT else 'refused'})")
    if PVE_URL:
        pve = pve_listener()
        threading.Thread(target=pve.serve_forever, daemon=True).start()
        log(f"Proxmox API proxy on https://{LISTEN_HOST}:{PVE_PORT}/api2/json/ -> {PVE_URL}")
    else:
        log("Proxmox API proxy disabled (BWS_BROKER_PVE_URL not set)")
    server.serve_forever()


if __name__ == "__main__":
    main()
