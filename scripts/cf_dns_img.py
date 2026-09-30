#!/usr/bin/env python3
"""Create/update Cloudflare A record for img.themarfa.name (DNS-only).

Target IPv4 is taken from ANCHOR_HOST (default bot.themarfa.name), never hardcoded.
"""
from __future__ import annotations

import json
import os
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

from dotenv import dotenv_values

ZONE_NAME = "themarfa.name"
RECORD_NAME = "img"
ANCHOR_HOST = os.environ.get("ANCHOR_HOST", "bot.themarfa.name")
TTL = 300


def load_token() -> str:
    env_token = os.environ.get("CLOUDFLARE_API_KEY") or os.environ.get("CF_API_TOKEN")
    if env_token:
        return env_token
    candidates = [
        Path(__file__).resolve().parents[2] / "ghost_translator_repo" / ".env",
        Path(__file__).resolve().parents[1] / ".env",
    ]
    for path in candidates:
        if path.is_file():
            vals = dotenv_values(path)
            token = vals.get("CLOUDFLARE_API_KEY") or vals.get("CF_API_TOKEN")
            if token:
                return token
    raise SystemExit("CLOUDFLARE_API_KEY not found in env or sibling .env")


def resolve_ipv4(host: str) -> str:
    infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    if not infos:
        raise SystemExit(f"no A record for {host}")
    return infos[0][4][0]


def cf(token: str, method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4{path}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Cloudflare {method} {path} failed: {exc.code} {detail}") from exc


def main() -> int:
    token = load_token()
    content = os.environ.get("VPS_PUBLIC_IPV4") or resolve_ipv4(ANCHOR_HOST)
    zones = cf(token, "GET", f"/zones?name={ZONE_NAME}")
    if not zones.get("success") or not zones.get("result"):
        raise SystemExit(f"zone lookup failed: {zones}")
    zone_id = zones["result"][0]["id"]
    existing = cf(
        token,
        "GET",
        f"/zones/{zone_id}/dns_records?name={RECORD_NAME}.{ZONE_NAME}&type=A",
    )
    payload = {
        "type": "A",
        "name": RECORD_NAME,
        "content": content,
        "ttl": TTL,
        "proxied": False,
        "comment": "Ghost storage.ghost.io image failover proxy",
    }
    if existing.get("result"):
        rid = existing["result"][0]["id"]
        out = cf(token, "PUT", f"/zones/{zone_id}/dns_records/{rid}", payload)
        action = "updated"
    else:
        out = cf(token, "POST", f"/zones/{zone_id}/dns_records", payload)
        action = "created"
    if not out.get("success"):
        raise SystemExit(out)
    result = out["result"]
    print(
        f"{action}: {result['name']} -> {result['content']} "
        f"proxied={result['proxied']} id={result['id']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
