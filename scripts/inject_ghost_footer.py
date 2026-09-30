#!/usr/bin/env python3
"""Inject fallback.js into Ghost Admin codeinjection_foot (append or replace block)."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import jwt
import urllib.error
import urllib.request
from dotenv import dotenv_values

MARKER_START = "<!-- ghost-img-proxy:start -->"
MARKER_END = "<!-- ghost-img-proxy:end -->"


def load_ghost() -> tuple[str, str]:
    candidates = [
        Path(__file__).resolve().parents[2] / "ghost_translator_repo" / ".env",
        Path(__file__).resolve().parents[1] / ".env",
    ]
    for path in candidates:
        if not path.is_file():
            continue
        vals = dotenv_values(path)
        url = (vals.get("SOURCE_GHOST_URL") or vals.get("GHOST_URL") or "").rstrip("/")
        key = vals.get("SOURCE_GHOST_ADMIN_API_KEY") or vals.get("GHOST_ADMIN_API_KEY")
        if url and key:
            return url, key
    raise SystemExit("SOURCE_GHOST_URL / SOURCE_GHOST_ADMIN_API_KEY not found")


def admin_token(admin_api_key: str) -> str:
    key_id, secret = admin_api_key.split(":")
    now = int(time.time())
    payload = {"iat": now, "exp": now + 5 * 60, "aud": "/admin/"}
    return jwt.encode(
        payload,
        bytes.fromhex(secret),
        algorithm="HS256",
        headers={"kid": key_id, "alg": "HS256", "typ": "JWT"},
    )


def api(url: str, token: str, method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{url}{path}",
        data=data,
        headers={
            "Authorization": f"Ghost {token}",
            "Content-Type": "application/json",
            "Accept-Version": "v5.0",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Ghost {method} {path} failed: {exc.code} {detail}") from exc


def upsert_footer(existing: str, snippet: str) -> str:
    block = f"{MARKER_START}\n<script>\n{snippet.strip()}\n</script>\n{MARKER_END}"
    if MARKER_START in existing and MARKER_END in existing:
        pre = existing.split(MARKER_START, 1)[0]
        post = existing.split(MARKER_END, 1)[1]
        return pre + block + post
    existing = existing.rstrip()
    if existing:
        return existing + "\n\n" + block + "\n"
    return block + "\n"


def main() -> int:
    ghost_url, admin_key = load_ghost()
    js_path = Path(__file__).resolve().parents[1] / "fallback.js"
    snippet = js_path.read_text(encoding="utf-8")
    token = admin_token(admin_key)
    settings_resp = api(ghost_url, token, "GET", "/ghost/api/admin/settings/")
    settings = settings_resp.get("settings") or []
    foot = ""
    for item in settings:
        if item.get("key") == "codeinjection_foot":
            foot = item.get("value") or ""
            break
    new_foot = upsert_footer(foot, snippet)
    body = {
        "settings": [
            {"key": "codeinjection_foot", "value": new_foot},
        ]
    }
    api(ghost_url, token, "PUT", "/ghost/api/admin/settings/", body)
    print(f"updated codeinjection_foot on {ghost_url} ({len(new_foot)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
