#!/usr/bin/env python3
"""Inline fallback.js into Blogtheme default.hbs via GitHub Contents API."""
from __future__ import annotations

import base64
import json
import re
import subprocess
import urllib.request
from pathlib import Path

JS = Path(__file__).resolve().parents[1] / "fallback.js"
REPO = "Marfa/Blogtheme"
PATH = "default.hbs"


def gh_token() -> str:
    return subprocess.check_output(["gh", "auth", "token"], text=True).strip()


def api(method: str, url_path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.github.com/{url_path}",
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {gh_token()}",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def main() -> None:
    js = JS.read_text(encoding="utf-8").strip()
    meta = api("GET", f"repos/{REPO}/contents/{PATH}?ref=master")
    text = base64.b64decode(meta["content"]).decode("utf-8")

    text = re.sub(
        r"\{\{!-- Ghost CDN image failover.*?--\}\}\s*"
        r"<script src=\"\{\{asset 'js/ghost-img-proxy\.js'\}\}\" defer></script>\s*",
        "",
        text,
        flags=re.S,
    )
    text = re.sub(
        r"\{\{!-- Ghost CDN image failover --\}\}\s*<script>.*?</script>\s*",
        "",
        text,
        flags=re.S,
    )

    inline = (
        "{{!-- Ghost CDN image failover --}}\n"
        f"<script>\n{js}\n</script>\n"
    )
    if "{{ghost_foot}}" not in text:
        raise SystemExit("{{ghost_foot}} not found in default.hbs")
    text = text.replace("{{ghost_foot}}", inline + "{{ghost_foot}}")

    out = api(
        "PUT",
        f"repos/{REPO}/contents/{PATH}",
        {
            "message": "Inline Ghost CDN image failover script in default.hbs",
            "content": base64.b64encode(text.encode("utf-8")).decode(),
            "branch": "master",
            "sha": meta["sha"],
        },
    )
    print("commit", out["commit"]["sha"])
    idx_feeds = text.find("feeds.themarfa.name/gimg")
    idx_img = text.find("https://img.themarfa.name")
    print("feeds_idx", idx_feeds, "img_idx", idx_img)


if __name__ == "__main__":
    main()
