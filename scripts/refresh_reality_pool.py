#!/usr/bin/env python3
"""Refresh the bundled community pool from a public aggregator, health-checked.

Fetches MhdiTaheri/V2rayCollector's mixed subscription, keeps VLESS+REALITY
(tcp) and VLESS+XHTTP entries, prefilters by TCP reachability, then dials each
survivor with a real Xray session and a fixed download — the same data-plane
proof scripts/probe_reality.py applies to the published pool. Only relays that
moved bytes are shipped, ranked by measured throughput with port 443 first
(Iran's standing whitelist forwards 53/80/443 and drops the rest).

REALITY entries stay structured so the app's ClientHello ladder applies;
XHTTP entries ship as share links because the link is the whole profile.
Ids are content hashes of host:port:uuid so a relay that survives a refresh
keeps its health history and its place in the phone's memory.

The current pool's relays are re-probed alongside the fresh candidates, so a
proven address is not dropped just because the aggregator rotated it out.

Usage:
  python3 scripts/refresh_reality_pool.py --xray /usr/local/bin/xray
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
import random
import socket
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlsplit
from urllib.request import Request, urlopen

import probe_reality

SOURCE_URL = (
    "https://raw.githubusercontent.com/MhdiTaheri/V2rayCollector/main/sub/mix"
)
NOTICE = (
    "Community-contributed REALITY/XHTTP relays. They are not private: the "
    "operator can see your traffic. They are dialled unless the user switches "
    "them off; the switch is in Settings."
)

# Fingerprint names the bundled core resolves (transport/internet/tls/tls.go).
# An unknown name would kill the dial with "failed to get fingerprint", so an
# entry publishing one is dialled as chrome instead.
CORE_FINGERPRINTS = {
    "chrome", "firefox", "safari", "ios", "edge", "qq", "random", "randomized",
    "randomizednoalpn", "unsafe", "hellochrome_120", "hellochrome_131",
    "hellochrome_133", "hellochrome_106_shuffle", "hellochrome_115_pq",
    "hellochrome_115_pq_psk", "hellochrome_120_pq", "hellochrome_auto",
    "hellofirefox_120", "hellofirefox_148", "hellofirefox_auto",
    "helloios_13", "helloios_14", "helloios_auto", "hellosafari_16_0",
    "hellosafari_26_3", "hellosafari_auto", "helloedge_106", "helloedge_auto",
    "hellogolang", "hellorandomized", "hellorandomizedalpn",
    "hellorandomizednoalpn",
}


def fetch_links(url: str) -> list[str]:
    request = Request(url, headers={"User-Agent": "bulbvpn-pool-refresh"})
    with urlopen(request, timeout=30) as response:
        body = response.read().decode("utf-8", errors="replace")
    # Aggregators HTML-escape query separators and sometimes base64 the body.
    body = html.unescape(body)
    if "://" not in body:
        try:
            body = base64.b64decode(body + "===").decode("utf-8", errors="replace")
            body = html.unescape(body)
        except Exception:
            pass
    return [line.strip() for line in body.splitlines() if "://" in line]


def flag_country(fragment: str) -> str:
    """A remark that starts with a flag emoji carries its country for free."""
    text = unquote(fragment)
    letters = []
    for ch in text:
        cp = ord(ch)
        if 0x1F1E6 <= cp <= 0x1F1FF:
            letters.append(chr(cp - 0x1F1E6 + ord("A")))
        elif letters:
            break
    return "".join(letters) if len(letters) == 2 else ""


def relay_id(host: str, port: int, uuid: str) -> str:
    digest = hashlib.sha1(f"{host}:{port}:{uuid}".encode()).hexdigest()
    return f"vc-{digest[:10]}"


def parse_link(link: str) -> dict | None:
    """One pool entry from a share link, or None for anything we don't ship."""
    try:
        parts = urlsplit(link)
        if parts.scheme != "vless" or not parts.hostname or not parts.username:
            return None
        port = parts.port or 443
        if not 1 <= port <= 65535:
            return None
        params = {
            k.lower(): v for k, v in parse_qsl(parts.query, keep_blank_values=True)
        }
        uuid = unquote(parts.username)
        host = parts.hostname
        network = params.get("type", "tcp").lower()
        security = params.get("security", "none").lower()
        country = flag_country(parts.fragment)
        base = {
            "id": relay_id(host, port, uuid),
            "host": host,
            "port": port,
            "country_code": country,
            "country_name": "",
            "city": "",
        }
        if security == "reality" and network == "tcp":
            sni = params.get("sni", "").strip()
            pbk = params.get("pbk", "").strip()
            if not sni or not pbk:
                return None
            fp = params.get("fp", "chrome").strip() or "chrome"
            return {
                **base,
                "uuid": uuid,
                "public_key": pbk,
                "short_id": params.get("sid", ""),
                "server_name": sni,
                "fingerprint": fp if fp in CORE_FINGERPRINTS else "chrome",
                "flow": params.get("flow", ""),
            }
        if network == "xhttp" and security in ("tls", "reality"):
            # The link is the profile; probe_reality.vless_link_outbound and
            # the app's flutter_vless parser both read it verbatim.
            return {**base, "uuid": uuid, "link": link}
        return None
    except (ValueError, TypeError):
        return None


def tcp_alive(entry: dict, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection((entry["host"], entry["port"]), timeout):
            return True
    except OSError:
        return False


def geolocate(entries: list[dict]) -> None:
    """Fill country for finalists whose remark carried no flag.

    ip-api's free tier is HTTP-only and keyed by IP, so domains are resolved
    first. One GET per finalist stays inside the 45/min free quota; the batch
    POST endpoint timed out from two different egresses on 2026-11-06 while
    the single-IP GET answered in 0.3s. A failed lookup leaves the country
    empty; the app then shows "Community relay", which is honest.
    """
    for entry in entries:
        if entry.get("country_code"):
            continue
        try:
            info = socket.getaddrinfo(entry["host"], None)
            ip = info[0][4][0]
            request = Request(
                f"http://ip-api.com/json/{ip}?fields=status,countryCode,country,city",
                headers={"User-Agent": "bulbvpn-pool-refresh"},
            )
            with urlopen(request, timeout=8) as response:
                row = json.loads(response.read().decode())
            if row.get("status") == "success":
                entry["country_code"] = (row.get("countryCode") or "").upper()
                entry["country_name"] = row.get("country") or ""
                entry["city"] = row.get("city") or ""
        except Exception as error:
            print(f"geolocation skipped for {entry['host']}: {error}", file=sys.stderr)
        time.sleep(1.4)


def load_current(path: Path) -> list[dict]:
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        return [
            entry
            for entry in catalog.get("relays", [])
            if probe_reality.valid_relay(entry)
        ]
    except (OSError, ValueError):
        return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=SOURCE_URL)
    parser.add_argument(
        "--out", default="assets/relays/community_reality.json"
    )
    parser.add_argument("--health-out", default="data/reality_health.json")
    parser.add_argument("--xray", default="xray")
    parser.add_argument("--reality-target", type=int, default=20)
    parser.add_argument("--xhttp-target", type=int, default=8)
    parser.add_argument("--max-reality-probes", type=int, default=150)
    parser.add_argument("--max-xhttp-probes", type=int, default=60)
    parser.add_argument("--probe-timeout", type=int, default=10)
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()

    links = fetch_links(args.source)
    print(f"fetched {len(links)} links from {args.source}", file=sys.stderr)

    out_path = Path(args.out)
    candidates: dict[str, dict] = {}
    # The shipped pool goes in first: a relay this build already trusts with
    # its history keeps its id when it survives the re-probe.
    for entry in load_current(out_path):
        entry.setdefault("country_code", "")
        entry.setdefault("country_name", "")
        entry.setdefault("city", "")
        candidates[entry["id"]] = entry
    current_ids = set(candidates)
    for link in links:
        entry = parse_link(link)
        if entry is not None:
            candidates.setdefault(entry["id"], entry)
    reality = [e for e in candidates.values() if not e.get("link")]
    xhttp = [e for e in candidates.values() if e.get("link")]
    print(
        f"candidates: {len(reality)} REALITY, {len(xhttp)} XHTTP "
        f"({len(current_ids)} carried over from the current pool)",
        file=sys.stderr,
    )

    with ThreadPoolExecutor(max_workers=24) as pool:
        alive = list(pool.map(tcp_alive, reality + xhttp))
    split = len(reality)
    reality = [e for e, ok in zip(reality, alive[:split]) if ok]
    xhttp = [e for e, ok in zip(xhttp, alive[split:]) if ok]
    print(
        f"TCP prefilter: {len(reality)} REALITY, {len(xhttp)} XHTTP reachable",
        file=sys.stderr,
    )

    # Rotate the probe window daily so the pool explores beyond the first
    # slice of the aggregator; carried-over relays are always probed.
    rng = random.Random(datetime.now(timezone.utc).date().toordinal())

    def window(entries: list[dict], cap: int) -> list[dict]:
        kept = [e for e in entries if e["id"] in current_ids]
        fresh = [e for e in entries if e["id"] not in current_ids]
        p443 = [e for e in fresh if e["port"] == 443]
        other = [e for e in fresh if e["port"] != 443]
        rng.shuffle(p443)
        rng.shuffle(other)
        return (kept + p443 + other)[:cap]

    probe_set = window(reality, args.max_reality_probes) + window(
        xhttp, args.max_xhttp_probes
    )
    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(
            pool.map(
                lambda e: probe_reality.probe(e, args.xray, args.probe_timeout),
                probe_set,
            )
        )
    by_id = {r["id"]: r for r in results}
    for result in results:
        state = "ok" if result["ok"] else "bad"
        print(
            f"{result['id']:16} {state:3} {result['bytes']:>6}B "
            f"{result['ms']:>5}ms {result['error']}",
            file=sys.stderr,
        )
    print(
        f"probed {len(results)} in {int(time.time() - started)}s",
        file=sys.stderr,
    )

    def select(entries: list[dict], target: int) -> list[dict]:
        healthy = [e for e in entries if by_id.get(e["id"], {}).get("ok")]
        healthy.sort(
            key=lambda e: (
                e["port"] != 443,
                -(by_id[e["id"]]["bytes"] * 1000 // max(by_id[e["id"]]["ms"], 1)),
            )
        )
        return healthy[:target]

    picked_reality = select(reality, args.reality_target)
    picked_xhttp = select(xhttp, args.xhttp_target)
    if len(picked_reality) < 5:
        print(
            f"only {len(picked_reality)} REALITY relays passed the data gate; "
            "keeping the current pool",
            file=sys.stderr,
        )
        return 1
    selected = picked_reality + picked_xhttp
    geolocate(selected)

    generated_at = datetime.now(timezone.utc).isoformat()
    catalog = {
        "version": 1,
        "generated_at": generated_at,
        "source": args.source,
        "notice": NOTICE,
        "relays": selected,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    probes = [by_id[e["id"]] for e in selected]
    health = {
        "schema": probe_reality.SCHEMA,
        "generated_at": generated_at,
        "catalog_generated_at": generated_at,
        "healthy": len(probes),
        "total": len(probes),
        "probes": probes,
    }
    health_path = Path(args.health_out)
    health_path.parent.mkdir(parents=True, exist_ok=True)
    health_path.write_text(
        json.dumps(health, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {len(picked_reality)} REALITY + {len(picked_xhttp)} XHTTP "
        f"to {out_path} and {health_path}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())