#!/usr/bin/env python3
"""Self-check for ghost-img-proxy helpers (path rewrite logic mirrored from fallback.js)."""
from __future__ import annotations


ORIGIN = "https://storage.ghost.io"
PROXY = "https://img.themarfa.name"


def to_proxy(url: str) -> str:
    if not url.startswith(ORIGIN):
        return url
    return PROXY + url[len(ORIGIN) :]


def rewrite_srcset(srcset: str) -> str:
    parts = []
    for part in srcset.split(","):
        bits = part.strip().split()
        if not bits:
            parts.append(part)
            continue
        bits[0] = to_proxy(bits[0])
        parts.append(" ".join(bits))
    return ", ".join(parts)


def main() -> None:
    src = f"{ORIGIN}/c/71/cf/x/content/images/a.jpg"
    assert to_proxy(src) == f"{PROXY}/c/71/cf/x/content/images/a.jpg"
    assert to_proxy("https://example.com/x.jpg") == "https://example.com/x.jpg"
    ss = f"{ORIGIN}/a.jpg 300w, {ORIGIN}/b.jpg 600w"
    assert rewrite_srcset(ss) == f"{PROXY}/a.jpg 300w, {PROXY}/b.jpg 600w"
    print("ok")


if __name__ == "__main__":
    main()
