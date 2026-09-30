#!/usr/bin/env bash
# Install/update Ghost image CDN failover proxy on the HostKey VPS.
# 1) Always enables https://feeds.themarfa.name/gimg/... (existing TLS)
# 2) If img.themarfa.name DNS points here, issues cert and enables dedicated vhost
set -euo pipefail

SITE_NAME="img.themarfa.name"
SITE_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
WEBROOT="/var/www/html"
SNIP_GIMG="/etc/nginx/snippets/ghost-img-gimg.conf"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${REPO_DIR}/nginx/img.themarfa.name.bootstrap.conf"
FULL_CONF="${REPO_DIR}/nginx/img.themarfa.name.conf"
GIMG_CONF="${REPO_DIR}/nginx/feeds-gimg.conf"
SMOKE_PATH="/c/71/cf/71cf070c-b8aa-467e-9efd-cf18f7dcf253/content/images/size/w30/2018/01/DSC_0094-3-.jpg"
VPS_IP="152.114.195.134"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

command -v nginx >/dev/null
command -v curl >/dev/null

mkdir -p "$WEBROOT" /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets

echo "==> install feeds /gimg snippet"
cp -a "$GIMG_CONF" "$SNIP_GIMG"

# Ensure feeds (or any site that serves feeds.themarfa.name) includes the snippet once.
include_gimg_in_feeds() {
  local conf
  for conf in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    [[ -f "$conf" ]] || continue
    if grep -q 'server_name.*feeds\.themarfa\.name' "$conf" 2>/dev/null; then
      if grep -q 'ghost-img-gimg.conf' "$conf"; then
        echo "gimg already included in $conf"
      else
        # Insert include inside the first server block that mentions feeds.
        cp -a "$conf" "${conf}.bak.$(date +%s)"
        awk '
          BEGIN { done=0 }
          /server_name/ && /feeds\.themarfa\.name/ && done==0 {
            print
            print "    include /etc/nginx/snippets/ghost-img-gimg.conf;"
            done=1
            next
          }
          { print }
        ' "$conf" > "${conf}.new"
        mv "${conf}.new" "$conf"
        echo "included gimg in $conf"
      fi
      return 0
    fi
  done
  echo "WARNING: no nginx site with server_name feeds.themarfa.name found" >&2
  return 1
}

include_gimg_in_feeds || true

nginx -t
systemctl reload nginx

echo "==> smoke feeds /gimg"
gimg_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
  "https://feeds.themarfa.name/gimg${SMOKE_PATH}" || echo fail)"
echo "feeds_gimg_http_code=${gimg_code}"
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
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
  "https://${SITE_NAME}${SMOKE_PATH}" || echo fail)"
echo "img_smoke_http_code=${code}"
if [[ "$code" != "200" ]]; then
  echo "WARNING: ${SITE_NAME} smoke did not return 200" >&2
  exit 1
fi
echo "OK: ${SITE_NAME} proxy ready"
