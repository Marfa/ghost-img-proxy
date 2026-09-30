# ghost-img-proxy

Failover proxy for Ghost(Pro) CDN images blocked on some networks (`storage.ghost.io` → `ERR_CONNECTION_RESET`).

## Live

| Endpoint | Role |
|----------|------|
| `https://feeds.themarfa.name/gimg/...` | Path-mirrored proxy on the HostKey VPS |
| `https://img.themarfa.name/...` | Dedicated host (same VPS; DNS A → same target as `bot.themarfa.name`, DNS-only) |
| Theme script / inline failover | Browsers try CDN first, then proxy on error |

Default: browsers still load `storage.ghost.io`. On `error`, JS rewrites to the proxy.

Same HostKey VPS / nginx pattern as `bot.themarfa.name`, `feeds.themarfa.name`, `ghost-translator.themarfa.name`.

## Layout

| Path | Purpose |
|------|---------|
| `nginx/feeds-gimg.conf` | `/gimg/` location for feeds.themarfa.name |
| `nginx/img.themarfa.name.conf` | Dedicated HTTPS site |
| `nginx/img.themarfa.name.bootstrap.conf` | HTTP ACME bootstrap |
| `fallback.js` | Browser failover |
| `scripts/install_vps.sh` | Root install on VPS |
| `scripts/cf_dns_img.py` | Cloudflare A record (DNS-only; IP from `bot.themarfa.name` / `VPS_PUBLIC_IPV4`) |

## DNS (img.themarfa.name)

Cloudflare → themarfa.name → Add record:

- Type **A**, Name **img**, IPv4 = same as `bot.themarfa.name`, Proxy **DNS only** (grey cloud)

Or with a valid API token (Zone DNS Edit):

```bash
export CLOUDFLARE_API_KEY=...
# optional: export VPS_PUBLIC_IPV4=...   # otherwise resolved from bot.themarfa.name
python scripts/cf_dns_img.py
```

## VPS install

```bash
bash scripts/install_vps.sh
```

Via GitHub Actions: `Marfa/ghost_translator` → **Install ghost-img-proxy** (secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`).

Smoke:

```text
https://feeds.themarfa.name/gimg/c/71/cf/.../content/images/...
https://img.themarfa.name/c/71/cf/.../content/images/...
```

## Author

Код подготовлен с помощью [Cursor](https://cursor.com).

| | |
| --- | --- |
| Донат | https://www.donationalerts.com/r/themarfa |
| Крипта | https://nowpayments.io/donation/themarfa |
