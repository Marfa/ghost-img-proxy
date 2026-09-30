#!/usr/bin/env bash
# Install/update Ghost image CDN failover proxy on the HostKey VPS.
# 1) Enables https://feeds.themarfa.name/gimg/... inside the existing FreshRSS vhost
# 2) If img.themarfa.name DNS points here, issues cert and enables dedicated vhost
set -euo pipefail

SITE_NAME="img.themarfa.name"
SITE_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
WEBROOT="/var/www/html"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${REPO_DIR}/nginx/img.themarfa.name.bootstrap.conf"
FULL_CONF="${REPO_DIR}/nginx/img.themarfa.name.conf"
GIMG_CONF="${REPO_DIR}/nginx/feeds-gimg.conf"
SMOKE_PATH="/c/71/cf/71cf070c-b8aa-467e-9efd-cf18f7dcf253/content/images/size/w30/2018/01/DSC_0094-3-.jpg"
# Never commit a literal VPS address — resolve the live HostKey box via bot anchor hostname.
VPS_IP="$(getent ahostsv4 bot.themarfa.name 2>/dev/null | awk '{print $1; exit}' || true)"
if [[ -z "${VPS_IP}" ]]; then
  VPS_IP="$(dig +short bot.themarfa.name A 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${VPS_IP}" ]]; then
  echo "ERROR: could not resolve bot.themarfa.name to an IPv4 address" >&2
  exit 1
fi
MARKER_BEGIN="# ghost-img-proxy:gimg:begin"
MARKER_END="# ghost-img-proxy:gimg:end"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

command -v nginx >/dev/null
command -v curl >/dev/null
command -v python3 >/dev/null

mkdir -p "$WEBROOT" /etc/nginx/sites-available /etc/nginx/sites-enabled

restore_if_broken() {
  local conf="$1"
  if nginx -t 2>/dev/null; then
    return 0
  fi
  local bak
  bak="$(ls -1t "${conf}.bak."* 2>/dev/null | head -n1 || true)"
  if [[ -n "$bak" ]]; then
    echo "nginx -t failed; restoring $bak"
    cp -a "$bak" "$conf"
  fi
}

find_feeds_conf() {
  local f
  for f in /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* /etc/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -qE 'server_name[[:space:]].*feeds\.themarfa\.name' "$f" 2>/dev/null; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

echo "==> patch feeds.themarfa.name with /gimg/ location"
FEEDS_CONF="$(find_feeds_conf || true)"
if [[ -z "${FEEDS_CONF}" ]]; then
  echo "ERROR: no nginx site with server_name feeds.themarfa.name found" >&2
  exit 1
fi
echo "feeds conf: ${FEEDS_CONF}"

# Ensure we start from a working config (undo earlier broken patches).
if ! nginx -t 2>/dev/null; then
  restore_if_broken "$FEEDS_CONF"
fi
# Drop any previous marker block / stray includes from earlier attempts.
python3 - "$FEEDS_CONF" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text2 = re.sub(
    r"\n?# ghost-img-proxy:gimg:begin.*?# ghost-img-proxy:gimg:end\n?",
    "\n",
    text,
    flags=re.S,
)
text2 = re.sub(
    r"\n?\s*include /etc/nginx/snippets/ghost-img-gimg\.conf;\n?",
    "\n",
    text2,
)
if text2 != text:
    path.write_text(text2, encoding="utf-8")
    print("stripped previous ghost-img-proxy fragments")
PY
restore_if_broken "$FEEDS_CONF"
nginx -t

if grep -q 'ghost-img-proxy:gimg:begin' "$FEEDS_CONF"; then
  echo "gimg location already present"
else
  # Keep backups outside sites-enabled — nginx include globs would load *.bak.*
  mkdir -p /root/nginx-site-backups
  cp -a "$FEEDS_CONF" "/root/nginx-site-backups/$(basename "$FEEDS_CONF").bak.$(date +%s)"
  python3 - "$FEEDS_CONF" "$GIMG_CONF" "$MARKER_BEGIN" "$MARKER_END" <<'PY'
from pathlib import Path
import sys
conf_path = Path(sys.argv[1])
gimg_path = Path(sys.argv[2])
begin, end = sys.argv[3], sys.argv[4]
block = gimg_path.read_text(encoding="utf-8").strip() + "\n"
lines = conf_path.read_text(encoding="utf-8").splitlines(keepends=True)
out = []
inserted = 0
for line in lines:
    out.append(line)
    # Patch EVERY feeds.themarfa.name server_name (HTTP + HTTPS vhosts).
    if (
        "server_name" in line
        and "feeds.themarfa.name" in line
        and not line.strip().startswith("#")
    ):
        out.append(f"\n    {begin}\n")
        for bl in block.splitlines():
            out.append(("    " + bl if bl.strip() else bl) + "\n")
        out.append(f"    {end}\n\n")
        inserted += 1
if inserted == 0:
    raise SystemExit("could not find server_name feeds.themarfa.name line")
conf_path.write_text("".join(out), encoding="utf-8")
print(f"inserted /gimg/ into {inserted} server_name block(s) in {conf_path}")
PY
fi

if ! nginx -t; then
  restore_if_broken "$FEEDS_CONF"
  nginx -t
  echo "ERROR: feeds patch failed nginx -t" >&2
  exit 1
fi

systemctl reload nginx

echo "==> smoke feeds /gimg"
gimg_code="fail"
for attempt in 1 2 3 4 5; do
  gimg_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "https://feeds.themarfa.name/gimg${SMOKE_PATH}" || echo fail)"
  echo "feeds_gimg_http_code=${gimg_code} attempt=${attempt}"
  if [[ "$gimg_code" == "200" ]]; then
    break
  fi
  sleep 2
done
if [[ "$gimg_code" != "200" ]]; then
  echo "ERROR: feeds /gimg smoke failed" >&2
  exit 1
fi

resolved="$(getent ahostsv4 "$SITE_NAME" 2>/dev/null | awk '{print $1; exit}' || true)"
echo "img DNS resolves to: ${resolved:-<none>}"

if [[ "$resolved" != "$VPS_IP" ]]; then
  echo "NOTE: ${SITE_NAME} does not point to ${VPS_IP} yet — skipping dedicated vhost/certbot"
  echo "OK: interim proxy ready at https://feeds.themarfa.name/gimg/..."
  exit 0
fi

command -v certbot >/dev/null

install_conf() {
  local src="$1"
  cp -a "$src" "$SITE_AVAILABLE"
  ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
  nginx -t
  systemctl reload nginx
}

echo "==> bootstrap HTTP site for ${SITE_NAME}"
install_conf "$BOOTSTRAP"

if [[ ! -f "/etc/letsencrypt/live/${SITE_NAME}/fullchain.pem" ]]; then
  echo "==> certbot certificate"
  certbot certonly \
    --webroot -w "$WEBROOT" \
    -d "$SITE_NAME" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --keep-until-expiring
fi

if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
  echo "ERROR: missing /etc/letsencrypt/options-ssl-nginx.conf" >&2
  exit 1
fi
if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

echo "==> install HTTPS proxy site ${SITE_NAME}"
install_conf "$FULL_CONF"

echo "==> smoke ${SITE_NAME}"
# Fresh LE certs can race curl's first verify; retry briefly.
code="fail"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "https://${SITE_NAME}${SMOKE_PATH}" || echo fail)"
  echo "img_smoke_http_code=${code} attempt=${attempt}"
  if [[ "$code" == "200" ]]; then
    break
  fi
  sleep 3
done
if [[ "$code" != "200" ]]; then
  echo "WARNING: ${SITE_NAME} smoke did not return 200" >&2
  curl -v --connect-timeout 10 --max-time 30 -o /dev/null "https://${SITE_NAME}${SMOKE_PATH}" || true
  exit 1
fi
echo "OK: ${SITE_NAME} proxy ready"
