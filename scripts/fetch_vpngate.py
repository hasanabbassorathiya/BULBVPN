#!/usr/bin/env python3
"""Download the public VPN Gate CSV and write data/vpngate.json.

VPN Gate publishes this file for third-party clients:
https://www.vpngate.net/api/iphone/
The HostName column is a short label (public-vpn-160, vpn918840683). The
reachable DNS name is that label plus .opengw.net.
"""

from __future__ import annotations

import csv
import json
import sys
import urllib.request
from pathlib import Path

SOURCE = "https://www.vpngate.net/api/iphone/"
OUT = Path(__file__).resolve().parents[1] / "data" / "vpngate.json"
FIELDS = (
    "#HostName",
    "IP",
    "Score",
    "Ping",
    "Speed",
    "CountryLong",
    "CountryShort",
    "NumVpnSessions",
    "Uptime",
    "TotalUsers",
    "TotalTraffic",
    "LogType",
    "Operator",
    "Message",
    "OpenVPN_ConfigData_Base64",
)


def fqdn(host: str) -> str:
    host = host.strip()
    if not host or "." in host:
        return host
    return f"{host}.opengw.net"


def fetch_csv() -> str:
    request = urllib.request.Request(
        SOURCE,
        headers={"User-Agent": "BULBVPN-server-refresh"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", "replace")


def parse(body: str) -> list[dict[str, str]]:
    header = None
    rows: list[dict[str, str]] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("*"):
            continue
        if stripped.startswith("#") and "OpenVPN_ConfigData_Base64" in stripped:
            header = stripped.lstrip("#")
            continue
        if header is None or stripped.startswith("#"):
            continue
        values = next(csv.reader([stripped]))
        names = next(csv.reader([header]))
        if len(values) < len(names):
            continue
        row = {name: values[i].strip() for i, name in enumerate(names)}
        config = row.get("OpenVPN_ConfigData_Base64", "")
        ip = row.get("IP", "")
        if not config or not ip:
            continue
        row["#HostName"] = fqdn(row.get("HostName", "") or row.get("#HostName", ""))
        rows.append({key: row.get(key, "") for key in FIELDS})
    rows.sort(key=lambda row: int(row["Score"] or "0"), reverse=True)
    return rows


def main() -> int:
    body = fetch_csv()
    rows = parse(body)
    if len(rows) < 10:
        print(f"refusing to publish a short list ({len(rows)} rows)", file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    countries = {row["CountryLong"] for row in rows}
    print(f"wrote {len(rows)} servers across {len(countries)} countries to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
