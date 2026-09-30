# ghost-img-proxy

Failover proxy for Ghost(Pro) CDN images blocked on some networks (`storage.ghost.io` → `ERR_CONNECTION_RESET`).

- Public host: `https://img.themarfa.name`
- Upstream: `https://storage.ghost.io` (path-mirrored)
- Default: browsers still load `storage.ghost.io`
- On image `error`: Site Footer JS rewrites to this proxy for the rest of the tab

Same HostKey VPS / nginx pattern as `bot.themarfa.name`, `feeds.themarfa.name`, `ghost-translator.themarfa.name`.

## Layout

| Path | Purpose |
|------|---------|
| `nginx/img.themarfa.name.conf` | Production HTTPS nginx site |
| `nginx/img.themarfa.name.bootstrap.conf` | HTTP-only ACME bootstrap |
| `fallback.js` | Ghost Code Injection (Site Footer) |
| `scripts/install_vps.sh` | Root install on VPS |
| `scripts/cf_dns_img.py` | Cloudflare A record (DNS-only) |
| `scripts/inject_ghost_footer.py` | Push `fallback.js` into Ghost Admin settings |

## DNS

```bash
# needs CLOUDFLARE_API_KEY (API token) in env or ../ghost_translator_repo/.env
python scripts/cf_dns_img.py
```

Creates `img.themarfa.name` A `152.114.195.134`, **proxied=false**.

## VPS install

```bash
# on VPS as root, with this directory available:
bash scripts/install_vps.sh
```

Or via GitHub Actions SSH (secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`) — see workflow in deploy notes.

Smoke path:

`https://img.themarfa.name/c/71/cf/71cf070c-b8aa-467e-9efd-cf18f7dcf253/content/images/size/w30/2018/01/DSC_0094-3-.jpg`

## Ghost Code Injection

```bash
# SOURCE_GHOST_URL + SOURCE_GHOST_ADMIN_API_KEY from sibling .env
python scripts/inject_ghost_footer.py
```

Or paste `fallback.js` manually: Ghost Admin → Settings → Code injection → Site Footer.

## Author

Код подготовлен с помощью [Cursor](https://cursor.com).

| | |
| --- | --- |
| Донат | https://www.donationalerts.com/r/themarfa |
| Крипта | https://nowpayments.io/donation/themarfa |
