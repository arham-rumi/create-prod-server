# create-prod-server

> Scaffold a production-ready VPS config in one command.

<!-- DEMO GIF — record with `vhs` or `asciinema` and drop it here -->
<!-- ![demo](demo.gif) -->

```bash
npx create-prod-server
```

Answer four prompts. Get four files. Copy them to your server and run `setup.sh`.

---

## What it generates

| File | What it does |
|---|---|
| `nginx.conf` | Reverse-proxy to your Node app, HTTP→HTTPS redirect, security headers, gzip |
| `ecosystem.config.js` | PM2 cluster-mode config with logging and restart policy |
| `.env.example` | Environment variable template |
| `setup.sh` | Installs Node (via NVM), PM2, Nginx, configures UFW firewall, runs Certbot for SSL |

Everything is generated locally. The tool **does not SSH into your server** — you copy the files yourself and run `setup.sh` as root.

---

## Usage

```bash
npx create-prod-server
```

You'll be asked:

- **Domain name** — e.g. `example.com`
- **App name** — used in PM2 config and folder naming
- **Port** — the local port your Node app listens on (default: `3000`)
- **Node version** — installed via NVM (default: `20`)

Output lands in `./<app-name>-server-config/`.

---

## Deploying to your VPS

```bash
# 1. Copy the generated folder to your server
scp -r my-app-server-config/ root@your-server-ip:~/

# 2. SSH in
ssh root@your-server-ip

# 3. Run setup (installs everything and obtains SSL)
cd my-app-server-config
bash setup.sh

# 4. Upload your app, then start it
cd /var/www/my-app
pm2 start ecosystem.config.js
pm2 save
```

Tested on **Ubuntu 22.04 LTS** and **Ubuntu 24.04 LTS**.

---

## Requirements

- A fresh Ubuntu 22.04 or 24.04 VPS
- A domain pointed at your server's IP (A record for `@` and `www`)
- Root access

---

## Part of the "Building a Production Server from Scratch" series

This tool packages the exact workflow from the series:

- Part 1 — [Building a Production Server from Scratch — The Ultimate Guide](https://medium.com/@arhamrumi/building-a-production-server-from-scratch-the-ultimate-guide-637a77d9dc2d)
- Part 2 — [From Raw IP to Domain — Configuring Nginx Reverse Proxy](https://medium.com/javascript-in-plain-english/from-raw-ip-to-domain-configuring-nginx-reverse-proxy-18c5238c2d37)
- Part 3 — [Securing Your API with HTTPS — A Complete Guide to Free SSL Using Certbot](https://medium.com/javascript-in-plain-english/securing-your-api-with-https-a-complete-guide-to-free-ssl-using-certbot-bcdc6eb33fff)

---

## License

MIT
