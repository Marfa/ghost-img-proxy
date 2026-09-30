#!/usr/bin/env bash
# Install/update Ghost image CDN failover proxy on the HostKey VPS.
# 1) Enables https://feeds.themarfa.name/gimg/... inside the existing FreshRSS vhost
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
INCLUDE_LINE='    include /etc/nginx/snippets/ghost-img-gimg.conf;'

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

command -v nginx >/dev/null
command -v curl >/dev/null
command -v python3 >/dev/null

mkdir -p "$WEBROOT" /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets

echo "==> install feeds /gimg snippet"
cp -a "$GIMG_CONF" "$SNIP_GIMG"

restore_freshrss_if_broken() {
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

include_gimg_in_feeds() {
  local conf=""
  local f
  for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -q 'server_name.*feeds\.themarfa\.name' "$f" 2>/dev/null; then
      conf="$f"
      break
    fi
  done
  if [[ -z "$conf" ]]; then
    echo "WARNING: no nginx site with server_name feeds.themarfa.name found" >&2
    return 1
  fi

  if grep -q 'ghost-img-gimg.conf' "$conf"; then
    echo "gimg already included in $conf"
    return 0
  fi

  cp -a "$conf" "${conf}.bak.$(date +%s)"
  python3 - "$conf" "$INCLUDE_LINE" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
include_line = sys.argv[2]
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

# Find SSL server block that mentions feeds.themarfa.name, insert include
# once before its closing brace.
in_server = False
depth = 0
feeds_server = False
inserted = False
out = []
for line in lines:
    stripped = line.strip()
    if not in_server and stripped.startswith("server"):
        in_server = True
        depth = 0
        feeds_server = False
    if in_server:
        depth += line.count("{") - line.count("}")
        if "server_name" in line and "feeds.themarfa.name" in line:
            feeds_server = True
        if feeds_server and depth == 0 and stripped == "}" and not inserted:
            out.append(include_line + "\n")
            inserted = True
            in_server = False
            out.append(line)
            continue
        if depth == 0 and stripped == "}":
            in_server = False
    out.append(line)

if not inserted:
    sys.exit("could not find feeds.themarfa.name server block to patch")
path.write_text("".join(out), encoding="utf-8")
print(f"included gimg in {path}")
PY

  if ! nginx -t; then
    restore_freshrss_if_broken "$conf"
    nginx -t
    echo "ERROR: failed to include gimg safely" >&2
    return 1
  fi
}

# If a previous broken patch exists, restore newest bak before retrying.
for f in /etc/nginx/sites-enabled/freshrss /etc/nginx/sites-enabled/*; do
  [[ -f "$f" ]] || continue
  if grep -q 'server_name.*feeds\.themarfa\.name' "$f" 2>/dev/null; then
    if ! nginx -t 2>/dev/null; then
      restore_freshrss_if_broken "$f"
    fi
    break
  fi
done

include_gimg_in_feeds

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
