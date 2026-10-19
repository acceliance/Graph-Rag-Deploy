#!/usr/bin/env bash
# =============================================================================
#  Acceliance Graph-RAG — one-shot deployment on a fresh Debian server.
#
#  Installs and configures, in this order:
#    1. Docker Engine + Compose plugin (official Docker apt repository)
#    2. The Graph-RAG stack under /opt/graphrag (scripts/up.sh, bound to 127.0.0.1)
#    3. Apache as reverse proxy, listening on 443 ONLY, with a TLS certificate
#    4. ufw firewall: deny all incoming except 443/tcp and SSH (22/tcp)
#
#  Usage (as root, from a checkout of this repository):
#
#    sudo scripts/deploy-debian.sh --domain graphrag.example.com --email you@example.com
#
#  Certificate modes (pick one):
#    (default)               Let's Encrypt via certbot. Needs a public DNS record
#                            pointing to this server. Port 80 is opened ONLY for
#                            the seconds an issuance/renewal takes (HTTP-01), then
#                            closed again — it is never left open.
#    --cert F --key F        Use your own certificate (PEM fullchain + private key).
#    --self-signed           Self-signed certificate (tests only; browsers warn).
#
#  Options:
#    --domain NAME           Public FQDN of the server (required)
#    --email ADDR            Let's Encrypt account e-mail (required in LE mode)
#    --ssh-port N            SSH port to keep open (default: detected from sshd, else 22)
#    --install-dir DIR       Where the stack lives (default: /opt/graphrag)
#    --staging               Use the Let's Encrypt staging CA (avoids rate limits)
#
#  Idempotent: safe to run again (e.g. after a `git pull` to update the kit).
#  Data (./data) and secrets (.env) in the install dir are never overwritten.
# =============================================================================
set -euo pipefail

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DOMAIN=""; EMAIL=""; SSH_PORT=""; INSTALL_DIR="/opt/graphrag"
CERT_MODE="letsencrypt"; USER_CERT=""; USER_KEY=""; LE_STAGING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --domain)      DOMAIN="${2:-}"; shift 2;;
    --email)       EMAIL="${2:-}"; shift 2;;
    --ssh-port)    SSH_PORT="${2:-}"; shift 2;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2;;
    --cert)        USER_CERT="${2:-}"; CERT_MODE="custom"; shift 2;;
    --key)         USER_KEY="${2:-}"; CERT_MODE="custom"; shift 2;;
    --self-signed) CERT_MODE="selfsigned"; shift;;
    --staging)     LE_STAGING=1; shift;;
    -h|--help)     sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    *)             fail "unknown option: $1 (try --help)";;
  esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[ "$(id -u)" = "0" ] || fail "run as root (sudo)."
[ -r /etc/os-release ] || fail "/etc/os-release not found."
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "debian" ] || fail "this script targets Debian (detected: ${ID:-unknown})."
CODENAME="${VERSION_CODENAME:-}"; [ -n "$CODENAME" ] || fail "cannot detect the Debian codename."

[ -n "$DOMAIN" ] || fail "--domain is required."
[[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || fail "invalid domain: $DOMAIN"
case "$CERT_MODE" in
  letsencrypt) [ -n "$EMAIL" ] || fail "--email is required for Let's Encrypt.";;
  custom)      [ -r "$USER_CERT" ] && [ -r "$USER_KEY" ] || fail "--cert and --key must both be given and readable.";;
esac
[ -f "$SRC_ROOT/docker-compose.yaml" ] || fail "docker-compose.yaml not found in $SRC_ROOT (run from the repository)."

# SSH port: explicit > sshd effective config > 22. Opening the wrong one would lock us out.
if [ -z "$SSH_PORT" ]; then
  SSH_PORT="$( (sshd -T 2>/dev/null || true) | awk '$1=="port"{print $2; exit}')"
  SSH_PORT="${SSH_PORT:-22}"
fi
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] || fail "invalid SSH port: $SSH_PORT"

say "Deploying Graph-RAG for https://$DOMAIN  (cert: $CERT_MODE, ssh port: $SSH_PORT, dir: $INSTALL_DIR)"
if [ "$CERT_MODE" = "letsencrypt" ]; then
  echo "    DNS for $DOMAIN must already point to this server, or issuance will fail."
fi

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. Packages and Docker Engine
# ---------------------------------------------------------------------------
say "Installing base packages"
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl gnupg openssl rsync ufw apache2
if [ "$CERT_MODE" = "letsencrypt" ]; then
  apt-get install -y --no-install-recommends certbot
fi

if ! docker compose version >/dev/null 2>&1; then
  say "Installing Docker Engine (official repository)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

# ---------------------------------------------------------------------------
# 2. Graph-RAG stack — copy the kit, configure .env, start via scripts/up.sh
# ---------------------------------------------------------------------------
say "Installing the stack in $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
if [ "$(readlink -f "$SRC_ROOT")" != "$(readlink -f "$INSTALL_DIR")" ]; then
  rsync -a --exclude '.git' --exclude '/data' --exclude '/.env' "$SRC_ROOT"/ "$INSTALL_DIR"/
fi
cd "$INSTALL_DIR"

set_env() { # set_env KEY VALUE — replace the line, or append it
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else printf '%s=%s\n' "$1" "$2" >> .env; fi
}

# up.sh creates .env with generated secrets when missing; create it ourselves first
# so we can adjust the network settings before the first start.
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  set_env NEO4J_PASSWORD "$(openssl rand -base64 33 | tr -d '+/=\n' | cut -c1-32)"
  set_env QDRANT_API_KEY "$(openssl rand -base64 33 | tr -d '+/=\n' | cut -c1-32)"
fi
set_env GRAPHRAG_HTTP_BIND 127.0.0.1      # plain HTTP reachable from the host only
set_env GRAPHRAG_HTTP_PORT 8080
set_env AUTH_COOKIE_SECURE true           # we serve HTTPS
grep -q '^MCP_ALLOWED_HOSTS=.\+' .env || set_env MCP_ALLOWED_HOSTS "$DOMAIN:*"   # else clients get 421

bash scripts/up.sh

# ---------------------------------------------------------------------------
# 3a. Firewall — before exposing anything. SSH rule first so we never lock out.
# ---------------------------------------------------------------------------
say "Configuring the firewall (allow ${SSH_PORT}/tcp and 443/tcp only)"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 443/tcp comment 'HTTPS Graph-RAG'
ufw --force enable
# Docker only publishes 127.0.0.1:8080 (see .env), so it never bypasses ufw.

# ---------------------------------------------------------------------------
# 3b. TLS certificate
# ---------------------------------------------------------------------------
case "$CERT_MODE" in
  letsencrypt)
    say "Requesting a Let's Encrypt certificate (port 80 open only during issuance)"
    LE_ARGS=(certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
             --pre-hook  "/usr/sbin/ufw allow 80/tcp"
             --post-hook "/usr/sbin/ufw delete allow 80/tcp"
             --deploy-hook "/bin/systemctl reload apache2")
    [ "$LE_STAGING" = "1" ] && LE_ARGS+=(--staging)
    certbot "${LE_ARGS[@]}"
    # Port 80 must be free for the standalone authenticator: no Apache listener on 80 (see below).
    TLS_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    TLS_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    systemctl enable --now certbot.timer 2>/dev/null || true   # automatic renewal
    ;;
  custom)
    say "Installing the provided certificate"
    install -d -m 0750 /etc/graphrag/tls
    install -m 0644 "$USER_CERT" /etc/graphrag/tls/fullchain.pem
    install -m 0600 "$USER_KEY"  /etc/graphrag/tls/privkey.pem
    TLS_CERT=/etc/graphrag/tls/fullchain.pem; TLS_KEY=/etc/graphrag/tls/privkey.pem
    ;;
  selfsigned)
    say "Generating a self-signed certificate (tests only)"
    install -d -m 0750 /etc/graphrag/tls
    if [ ! -f /etc/graphrag/tls/privkey.pem ]; then
      openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
        -keyout /etc/graphrag/tls/privkey.pem -out /etc/graphrag/tls/fullchain.pem \
        -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN"
      chmod 600 /etc/graphrag/tls/privkey.pem
    fi
    TLS_CERT=/etc/graphrag/tls/fullchain.pem; TLS_KEY=/etc/graphrag/tls/privkey.pem
    ;;
esac

# ---------------------------------------------------------------------------
# 3c. Apache reverse proxy — 443 only (nothing listens on 80)
# ---------------------------------------------------------------------------
say "Configuring Apache (listening on 443 only)"
a2enmod ssl proxy proxy_http headers >/dev/null
a2dissite 000-default default-ssl >/dev/null 2>&1 || true
# Debian's ports.conf ships "Listen 80": replace it so only 443 is bound.
cat > /etc/apache2/ports.conf <<EOF
# Managed by scripts/deploy-debian.sh
Listen 443
EOF
cat > /etc/apache2/sites-available/graphrag.conf <<EOF
# Managed by scripts/deploy-debian.sh — edits are overwritten on the next run.
<VirtualHost *:443>
    ServerName $DOMAIN

    SSLEngine on
    SSLProtocol -all +TLSv1.2 +TLSv1.3
    SSLCertificateFile    $TLS_CERT
    SSLCertificateKeyFile $TLS_KEY
    Header always set Strict-Transport-Security "max-age=31536000"

    # >= GRAPHRAG_MAX_UPLOAD_MB (50), in bytes, with headroom
    LimitRequestBody 62914560

    # Keep Host (with port) for the MCP allow-list; long timeout for the agent loop.
    ProxyPreserveHost On
    ProxyTimeout 300
    RequestHeader set X-Forwarded-Proto "https"

    ProxyPass        / http://127.0.0.1:8080/ retry=0
    ProxyPassReverse / http://127.0.0.1:8080/
</VirtualHost>
EOF
a2ensite graphrag >/dev/null
apache2ctl configtest
systemctl enable apache2
systemctl restart apache2

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
say "Verifying"
ufw status verbose | sed 's/^/    /'
code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" || echo 000)"
echo "    https://$DOMAIN/ -> HTTP $code (via 127.0.0.1)"
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$'; then
  warn "something is listening on port 80 (blocked by the firewall, but check it)."
fi

say "Done:  https://$DOMAIN"
echo "    First visit: create the administrator account, then Admin > AI settings."
echo "    Secrets: $INSTALL_DIR/.env (mode 600) — back it up. Data: $INSTALL_DIR/data (scripts/backup.sh)."
[ "$CERT_MODE" = "letsencrypt" ] && echo "    Certificate renews automatically (certbot.timer); port 80 opens only during renewal."
exit 0
