#!/usr/bin/env bash
set -euo pipefail

# ── Config (filled in by create-prod-server) ─────────────────────────────────
DOMAIN="{{DOMAIN}}"
APP_NAME="{{APP_NAME}}"
APP_PORT="{{APP_PORT}}"
NODE_VERSION="{{NODE_VERSION}}"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
skip()    { echo -e "${YELLOW}[skip]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_INSTALL=false

for arg in "$@"; do
  case $arg in
    --skip-install) SKIP_INSTALL=true ;;
    *) die "Unknown argument: $arg. Usage: bash setup.sh [--skip-install]" ;;
  esac
done
# ─────────────────────────────────────────────────────────────────────────────

require_root() {
  [[ $EUID -eq 0 ]] || die "Run this script as root: sudo bash setup.sh"
}

detect_ubuntu() {
  . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release"
  [[ "$ID" == "ubuntu" ]] || die "This script targets Ubuntu. Detected: $ID"
  info "Ubuntu $VERSION_ID detected"

  case "$VERSION_ID" in
    22.04) ;;
    24.04) ;;
    *) warn "Untested on Ubuntu $VERSION_ID — proceeding anyway" ;;
  esac
}

install_dependencies() {
  info "Updating package lists…"
  apt-get update -qq

  info "Installing base dependencies…"
  # apt-get skips packages that are already up-to-date, so this is always safe
  apt-get install -y -qq \
    curl git ufw nginx certbot python3-certbot-nginx \
    build-essential dnsutils
}

install_nvm_node() {
  export NVM_DIR="/root/.nvm"

  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    skip "NVM already installed — loading existing installation"
    . "$NVM_DIR/nvm.sh"
  else
    info "Installing NVM…"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
  fi

  if nvm ls "$NODE_VERSION" &>/dev/null; then
    skip "Node.js $NODE_VERSION already installed via NVM"
    nvm use "$NODE_VERSION"
  else
    info "Installing Node.js $NODE_VERSION via NVM…"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use default
  fi

  # Refresh system-wide symlinks regardless (safe to re-run)
  NODE_BIN_DIR="$(nvm which default | xargs dirname)"
  ln -sf "$NODE_BIN_DIR/node" /usr/local/bin/node
  ln -sf "$NODE_BIN_DIR/npm"  /usr/local/bin/npm
  ln -sf "$NODE_BIN_DIR/npx"  /usr/local/bin/npx

  info "Node $(node -v) ready"
}

install_pm2() {
  if command -v pm2 &>/dev/null; then
    skip "PM2 already installed ($(pm2 -v)) — skipping"
    return
  fi

  info "Installing PM2 globally…"
  npm install -g pm2 --quiet
  pm2 startup systemd -u root --hp /root | tail -1 | bash || true
  info "PM2 installed and startup configured"
}

configure_firewall() {
  if ufw status | grep -q "Status: active"; then
    skip "UFW already active — ensuring Nginx Full is allowed…"
    ufw allow ssh
    ufw allow 'Nginx Full'
    info "Firewall rules verified"
    return
  fi

  info "Configuring UFW firewall…"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 'Nginx Full'
  ufw --force enable
  info "Firewall active — SSH, HTTP, HTTPS allowed"
}

configure_nginx() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ ! -f "$SCRIPT_DIR/nginx.conf" ]]; then
    die "nginx.conf not found next to setup.sh at $SCRIPT_DIR"
  fi

  info "Setting up temporary HTTP config so Certbot can complete its ACME challenge…"

  # Step 1: plain HTTP-only config — Certbot needs port 80 to verify the domain
  cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root /var/www/html;
}
EOF

  ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-enabled/default

  nginx -t && systemctl reload nginx
  info "Nginx running on HTTP — ready for Certbot"
}

obtain_ssl() {
  info "Checking DNS — verifying $DOMAIN resolves to this server…"

  # Ensure dig is available even when --skip-install was used
  command -v dig &>/dev/null || apt-get install -y -qq dnsutils

  SERVER_IP="$(curl -fsSL https://api.ipify.org 2>/dev/null || true)"
  DOMAIN_IP="$(dig +short "$DOMAIN" | tail -1)"

  if [[ -z "$DOMAIN_IP" ]]; then
    die "DNS lookup for $DOMAIN returned nothing. Make sure your A record points to this server and has propagated, then re-run."
  fi

  if [[ -n "$SERVER_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    warn "DNS mismatch: $DOMAIN resolves to $DOMAIN_IP but this server's IP is $SERVER_IP"
    warn "Certbot will likely fail. Make sure your A record is correct and DNS has propagated."
    warn "Proceeding anyway — press Ctrl+C to abort."
    sleep 5
  else
    info "DNS OK — $DOMAIN → $DOMAIN_IP"
  fi

  info "Obtaining SSL certificate via Certbot…"

  # certonly = get the cert only, do not let Certbot rewrite our nginx config.
  # --nginx  = use the Nginx plugin for the ACME HTTP-01 challenge (port 80).
  # Afterwards we copy our clean production nginx.conf into place ourselves.
  certbot certonly \
    --nginx \
    -d "$DOMAIN" \
    -d "www.$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  cp "$SCRIPT_DIR/nginx.conf" /etc/nginx/sites-available/$DOMAIN

  nginx -t && systemctl reload nginx
  info "SSL certificate installed. HTTPS active."
}

print_next_steps() {
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Setup complete for $DOMAIN${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Next steps:"
  echo "  1. Upload your app to /var/www/$APP_NAME (or your preferred path)"
  echo "  2. Copy ecosystem.config.js into the app root"
  echo "  3. Copy .env.example to .env and fill in your values"
  echo "  4. cd into your app and run:"
  echo "       npm install --production"
  echo "       pm2 start ecosystem.config.js"
  echo "       pm2 save"
  echo ""
  echo "  Your app will be live at https://$DOMAIN"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_root
detect_ubuntu

if [[ "$SKIP_INSTALL" == true ]]; then
  echo ""
  warn "--skip-install set: skipping Node, PM2, and firewall setup"
  warn "Assuming they are already configured on this VPS"
  echo ""
else
  install_dependencies
  install_nvm_node
  install_pm2
  configure_firewall
fi

configure_nginx
obtain_ssl
print_next_steps
