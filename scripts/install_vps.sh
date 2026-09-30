#!/usr/bin/env bash
# Install/update img.themarfa.name nginx proxy on the HostKey VPS.
# Run as root on the VPS, or via SSH from CI.
set -euo pipefail

SITE_NAME="img.themarfa.name"
SITE_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
WEBROOT="/var/www/html"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${REPO_DIR}/nginx/img.themarfa.name.bootstrap.conf"
FULL_CONF="${REPO_DIR}/nginx/img.themarfa.name.conf"
SMOKE_PATH="/c/71/cf/71cf070c-b8aa-467e-9efd-cf18f7dcf253/content/images/size/w30/2018/01/DSC_0094-3-.jpg"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

command -v nginx >/dev/null
command -v certbot >/dev/null

mkdir -p "$WEBROOT" /etc/nginx/sites-available /etc/nginx/sites-enabled

install_conf() {
  local src="$1"
  cp -a "$src" "$SITE_AVAILABLE"
  ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
  nginx -t
  systemctl reload nginx
}

echo "==> bootstrap HTTP site (ACME)"
install_conf "$BOOTSTRAP"

if [[ ! -f "/etc/letsencrypt/live/${SITE_NAME}/fullchain.pem" ]]; then
  echo "==> certbot certificate"
  # Prefer an existing admin email from another cert account if present.
  EMAIL_ARGS=(--register-unsafely-without-email)
  if [[ -f /etc/letsencrypt/accounts ]]; then
    EMAIL_ARGS=(--register-unsafely-without-email)
  fi
  certbot certonly \
    --webroot -w "$WEBROOT" \
    -d "$SITE_NAME" \
    --non-interactive \
    --agree-tos \
    "${EMAIL_ARGS[@]}" \
    --keep-until-expiring
fi

# Ensure ssl snippets exist (certbot usually installs these).
if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
  echo "ERROR: missing /etc/letsencrypt/options-ssl-nginx.conf (install python3-certbot-nginx once)" >&2
  exit 1
fi
if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

echo "==> install HTTPS proxy site"
install_conf "$FULL_CONF"

echo "==> smoke local"
curl -fsS --connect-timeout 5 --max-time 10 "https://127.0.0.1/health" -H "Host: ${SITE_NAME}" -k >/dev/null || true
curl -fsSI --connect-timeout 10 --max-time 30 "https://${SITE_NAME}${SMOKE_PATH}" | head -n 15
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "https://${SITE_NAME}${SMOKE_PATH}" || echo fail)"
echo "smoke_http_code=${code}"
if [[ "$code" != "200" ]]; then
  echo "WARNING: smoke did not return 200" >&2
  exit 1
fi
echo "OK: ${SITE_NAME} proxy ready"
