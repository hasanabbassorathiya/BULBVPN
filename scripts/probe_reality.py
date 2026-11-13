#!/usr/bin/env python3
"""Probe bundled REALITY/XHTTP relays with a real VLESS session.

Runs in GitHub Actions on a schedule. A TLS handshake only proves a host is
reachable; this script starts Xray-core with the same outbound the app builds,
fetches a fixed payload through the SOCKS listener, and records what actually
arrived. The published file is keyed by catalog id and carries measurements
only — never endpoints — so a tampered CDN response can reorder known relays
but cannot inject an unknown one.

Usage:
  python3 scripts/probe_reality.py --catalog assets/relays/community_reality.json \
      --out data/reality_health.json --xray /usr/local/bin/xray
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlsplit

PROBE_URL = "https://speed.cloudflare.com/__down?bytes=65536"
MIN_BYTES = 64 * 1024
SCHEMA = 1


def free_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def vless_link_outbound(link: str) -> dict:
    """The outbound a vless:// share link describes, tagged for the probe.

    Only what the pool ships is expressed here: VLESS over xhttp (tls or
    reality). The app parses links with flutter_vless; this mirrors the same
    stream settings so the measurement describes the dial the phone makes.
    """
    parts = urlsplit(link.strip())
    if parts.scheme != "vless" or not parts.hostname or not parts.username:
        raise ValueError("not a vless link with host and uuid")
    params = {k.lower(): v for k, v in parse_qsl(parts.query, keep_blank_values=True)}
    network = params.get("type", "tcp").lower()
    security = params.get("security", "none").lower()
    user = {"id": unquote(parts.username), "encryption": "none", "level": 0}
    flow = params.get("flow", "").strip()
    if flow:
        user["flow"] = flow
    stream: dict = {"network": network, "security": security}
    sni = params.get("sni") or params.get("peer") or ""
    fp = params.get("fp") or "chrome"
    if security == "tls":
        tls: dict = {"serverName": sni, "fingerprint": fp}
        alpn = params.get("alpn", "")
        if alpn:
            tls["alpn"] = alpn.split(",")
        stream["tlsSettings"] = tls
    elif security == "reality":
        stream["realitySettings"] = {
            "serverName": sni,
            "fingerprint": fp,
            "publicKey": params.get("pbk", ""),
            "shortId": params.get("sid", ""),
        }
    if network == "xhttp":
        settings: dict = {"path": params.get("path", "/") or "/"}
        if params.get("host"):
            settings["host"] = params["host"]
        if params.get("mode"):
            settings["mode"] = params["mode"]
        stream["xhttpSettings"] = settings
    elif network == "ws":
        stream["wsSettings"] = {
            "path": params.get("path", "/") or "/",
            "headers": {"Host": params.get("host", sni)},
        }
    elif network == "grpc":
        stream["grpcSettings"] = {"serviceName": params.get("serviceName", "")}
    return {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {
            "vnext": [
                {
                    "address": parts.hostname,
                    "port": parts.port or 443,
                    "users": [user],
                }
            ]
        },
        "streamSettings": stream,
    }


def xray_config(relay: dict, port: int) -> dict:
    inbound = {
        "tag": "socks-in",
        "listen": "127.0.0.1",
        "port": port,
        "protocol": "socks",
        "settings": {"udp": False},
    }
    link = (relay.get("link") or "").strip()
    if link:
        return {
            "log": {"loglevel": "warning"},
            "inbounds": [inbound],
            "outbounds": [vless_link_outbound(link)],
        }
    user = {"id": relay["uuid"], "encryption": "none", "level": 0}
    flow = (relay.get("flow") or "").strip()
    if flow:
        user["flow"] = flow
    return {
        "log": {"loglevel": "warning"},
        "inbounds": [inbound],
        "outbounds": [
            {
                "tag": "proxy",
                "protocol": "vless",
                "settings": {
                    "vnext": [
                        {
                            "address": relay["host"],
                            "port": int(relay["port"]),
                            "users": [user],
                        }
                    ]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "serverName": relay["server_name"],
                        "fingerprint": relay.get("fingerprint") or "chrome",
                        "publicKey": relay["public_key"],
                        "shortId": relay.get("short_id") or "",
                    },
                },
            }
        ],
    }


def valid_relay(relay: dict) -> bool:
    if not isinstance(relay, dict):
        return False
    for field in ("id", "host", "port"):
        if not str(relay.get(field) or "").strip():
            return False
    try:
        port = int(relay["port"])
    except (TypeError, ValueError):
        return False
    if not 1 <= port <= 65535:
        return False
    if str(relay.get("link") or "").strip():
        return True
    return all(
        str(relay.get(field) or "").strip()
        for field in ("uuid", "public_key", "server_name")
    )


def wait_for_port(port: int, proc: subprocess.Popen, seconds: float = 5.0) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def probe(relay: dict, xray: str, timeout: int) -> dict:
    relay_id = relay["id"]
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="reality-probe-") as tmp:
        config_path = Path(tmp) / "config.json"
        config_path.write_text(json.dumps(xray_config(relay, port)), encoding="utf-8")
        body_path = Path(tmp) / "body.bin"
        proc = subprocess.Popen(
            [xray, "run", "-c", str(config_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            if not wait_for_port(port, proc):
                return {
                    "id": relay_id,
                    "ok": False,
                    "bytes": 0,
                    "ms": 0,
                    "error": "client did not start",
                }
            started = time.time()
            result = subprocess.run(
                [
                    "curl",
                    "-sS",
                    "--max-time",
                    str(timeout),
                    "--socks5-hostname",
                    f"127.0.0.1:{port}",
                    "-o",
                    str(body_path),
                    "-w",
                    "%{http_code}",
                    PROBE_URL,
                ],
                capture_output=True,
                text=True,
                timeout=timeout + 5,
            )
            elapsed_ms = int((time.time() - started) * 1000)
            received = body_path.stat().st_size if body_path.exists() else 0
            status = (result.stdout or "").strip()
            ok = result.returncode == 0 and received >= MIN_BYTES
            error = ""
            if not ok:
                error = (
                    result.stderr.strip()
                    or f"http {status or 'none'}, {received} bytes"
                )[:140]
            return {
                "id": relay_id,
                "ok": ok,
                "bytes": received,
                "ms": elapsed_ms,
                "error": error,
            }
        except subprocess.TimeoutExpired:
            return {
                "id": relay_id,
                "ok": False,
                "bytes": 0,
                "ms": timeout * 1000,
                "error": "probe timed out",
            }
        except Exception as error:  # a broken entry must not stop the round
            return {
                "id": relay_id,
                "ok": False,
                "bytes": 0,
                "ms": 0,
                "error": f"{type(error).__name__}: {error}"[:140],
            }
        finally:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        default="assets/relays/community_reality.json",
        help="bundled REALITY catalog to probe",
    )
    parser.add_argument(
        "--out",
        default="data/reality_health.json",
        help="where to write the measurements",
    )
    parser.add_argument("--xray", default=os.environ.get("XRAY_BIN", "xray"))
    parser.add_argument("--timeout", type=int, default=12)
    parser.add_argument(
        "--only",
        default="",
        help="comma-separated relay ids, for local testing",
    )
    args = parser.parse_args()

    catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))
    relays = [relay for relay in catalog.get("relays", []) if valid_relay(relay)]
    only = {part.strip() for part in args.only.split(",") if part.strip()}
    if only:
        relays = [relay for relay in relays if relay["id"] in only]
    if not relays:
        print("no valid relays to probe", file=sys.stderr)
        return 1

    probes = []
    for relay in relays:
        result = probe(relay, args.xray, args.timeout)
        probes.append(result)
        state = "ok" if result["ok"] else "bad"
        print(
            f"{result['id']:20} {state:3} {result['bytes']:>6}B "
            f"{result['ms']:>5}ms {result['error']}",
            file=sys.stderr,
        )

    healthy = sum(1 for probe_result in probes if probe_result["ok"])
    payload = {
        "schema": SCHEMA,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "catalog_generated_at": catalog.get("generated_at", ""),
        "healthy": healthy,
        "total": len(probes),
        "probes": probes,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {healthy}/{len(probes)} healthy to {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
