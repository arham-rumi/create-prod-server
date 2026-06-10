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
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

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
  apt-get install -y -qq \
    curl git ufw nginx certbot python3-certbot-nginx \
    build-essential
}

install_nvm_node() {
  info "Installing NVM…"
  # Install for root; runs non-interactively
  export NVM_DIR="/root/.nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

  # Load NVM in this shell session
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"

  info "Installing Node.js $NODE_VERSION via NVM…"
  nvm install "$NODE_VERSION"
  nvm alias default "$NODE_VERSION"
  nvm use default

  # Make node/npm available system-wide via symlinks
  NODE_BIN_DIR="$(nvm which default | xargs dirname)"
  ln -sf "$NODE_BIN_DIR/node" /usr/local/bin/node
  ln -sf "$NODE_BIN_DIR/npm"  /usr/local/bin/npm
  ln -sf "$NODE_BIN_DIR/npx"  /usr/local/bin/npx

  info "Node $(node -v) ready"
}

install_pm2() {
  info "Installing PM2 globally…"
  npm install -g pm2 --quiet
  pm2 startup systemd -u root --hp /root | tail -1 | bash || true
  info "PM2 installed and startup configured"
}

configure_firewall() {
  info "Configuring UFW firewall…"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 'Nginx Full'   # ports 80 + 443
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
  info "Obtaining SSL certificate via Certbot…"

  # certbot --nginx edits whatever config is active for the domain.
  # We give it the plain HTTP config; it adds SSL directives there.
  # Afterwards we replace the whole file with our clean nginx.conf
  # (which has proper SSL, security headers, and gzip already set up).
  certbot certonly \
    --nginx \
    -d "$DOMAIN" \
    -d "www.$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Replace the Certbot-modified stub with our production-grade config
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
install_dependencies
install_nvm_node
install_pm2
configure_firewall
configure_nginx
obtain_ssl
print_next_steps
