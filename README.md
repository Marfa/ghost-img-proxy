# ghost-img-proxy

Failover proxy for Ghost(Pro) CDN images blocked on some networks (`storage.ghost.io` → `ERR_CONNECTION_RESET`).

## Live now

| Endpoint | Status |
|----------|--------|
| `https://feeds.themarfa.name/gimg/...` | **live** path-mirrored proxy on HostKey VPS |
| Theme script `assets/js/ghost-img-proxy.js` | **live** on blog.themarfa.name (onerror failover) |
| `https://img.themarfa.name/...` | ready in nginx install; needs DNS A → `152.114.195.134` (DNS-only) |

Default: browsers still load `storage.ghost.io`. On `error`, JS rewrites to `feeds.themarfa.name/gimg` (then `img.themarfa.name` if configured).

Same HostKey VPS / nginx pattern as `bot.themarfa.name`, `feeds.themarfa.name`, `ghost-translator.themarfa.name`.

## Layout

| Path | Purpose |
|------|---------|
| `nginx/feeds-gimg.conf` | `/gimg/` location for feeds.themarfa.name |
| `nginx/img.themarfa.name.conf` | Dedicated HTTPS site (after DNS+certbot) |
| `nginx/img.themarfa.name.bootstrap.conf` | HTTP ACME bootstrap |
| `fallback.js` | Browser failover (also shipped in Blogtheme) |
| `scripts/install_vps.sh` | Root install on VPS |
| `scripts/cf_dns_img.py` | Cloudflare A record (DNS-only) |

## DNS (img.themarfa.name)

Cloudflare → themarfa.name → Add record:

- Type **A**, Name **img**, IPv4 **152.114.195.134**, Proxy **DNS only** (grey cloud)

Or with a valid API token (Zone DNS Edit):

```bash
export CLOUDFLARE_API_KEY=...
python scripts/cf_dns_img.py
```

Then re-run VPS install / `Install ghost-img-proxy` workflow to issue Let’s Encrypt for the dedicated host.

## VPS install

```bash
bash scripts/install_vps.sh
```

Via GitHub Actions on `Marfa/ghost_translator`: workflow **Repair FreshRSS nginx + install gimg** (secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`).

Smoke:

`https://feeds.themarfa.name/gimg/c/71/cf/71cf070c-b8aa-467e-9efd-cf18f7dcf253/content/images/size/w30/2018/01/DSC_0094-3-.jpg`

## Author

Код подготовлен с помощью [Cursor](https://cursor.com).

| | |
| --- | --- |
| Донат | https://www.donationalerts.com/r/themarfa |
| Крипта | https://nowpayments.io/donation/themarfa |
