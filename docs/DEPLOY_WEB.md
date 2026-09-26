# Deploying the website + relay

`web/` is one Next.js app serving two hostnames: `velorki.com` (site, docs,
legal, `/s/<id>` share pages) and `api.velorki.com` (the relay: OAuth exchange,
`/ai/plan`, `POST /share`, `/health`). It runs on a VPS as a two-worker Orkify
cluster behind a reverse proxy — Caddy on a box of its own, nginx on a box that
already has one — behind Cloudflare.

Bare Ubuntu 24.04 to production, in order. Files referenced here live in
`deploy/web/` and `web/orkify.yml`. Local development is `web/README.md`.
If the box is not bare, read **Sharing a box** below first: it lists the steps
that change.

```
Cloudflare (proxied, Full strict)
   │ 443, only Cloudflare's ranges reach the box (ufw)
   ▼
Caddy or nginx ── Origin CA cert, Cloudflare trusted as the proxy,
   │               Host preserved
   │ 127.0.0.1:8080
   ▼
orkify cluster "velorki-web" ── 2 workers, .next/standalone/server.js
   │
   ├── /var/lib/velorki/share.sqlite   (persistent, outside the release tree)
   └── @orkify/cache                    (rate limits, entitlements, LLM budget)
```

---

## Sharing a box

The official deployment is not a bare VPS: it is the box that already serves
Orkify's own site, with nginx on 80 and 443 and its processes owned by an
`orkify` user. Everything below still applies, with these differences. Two
commands settle most of it:

```sh
ss -ltnp | grep -E ':(80|443|8080) '     # what already listens, and as whom
systemctl is-active nginx caddy          # which proxy is in charge
```

| Step | On a shared box |
|---|---|
| 1 | Add the `velorki` user; leave the existing user, SSH config and firewall alone. |
| 2 | **Skip the Node install** when `node -v` is already 22.13 or newer (`node:sqlite` is unflagged from there). Run `orkify autostart` **as the new user**: the unit is per user, so `orkify`'s processes and `velorki`'s are separate sets that restart independently. |
| 3 | `/var/log/caddy` is not needed. Install `cloudflare-ips-nginx.sh`, not `cloudflare-ips.sh`. |
| 4 | **4b, not 4a.** Do not install Caddy — two proxies cannot share 443. One Origin CA certificate **per domain**: velorki.com gets its own under `/etc/ssl/velorki/`, the other site keeps its own. |
| 3, 4b | **Do not let the Cloudflare IP script rewrite the firewall.** `cloudflare-ips-nginx.sh` deliberately does not touch ufw: the rules are shared with the other site. It prints the `ufw allow` lines it would have added; apply them by hand once you know they do not lock the neighbour out. |
| 6 | Pick a port nothing else holds. 8080 is free on this box; if it were not, change `port:` **and** `env.PORT` in `web/orkify.yml` and the `proxy_pass` in the nginx config together — they must agree or the health probe dials a closed socket. |

Everything else — the directories, the cron jobs, the deploy key and the
forced command, the Cloudflare zone, backups, operations — is the same on a
shared box as on a fresh one, because all of it is scoped to the `velorki`
user, `/srv/velorki`, `/var/lib/velorki` and the `velorki.com` zone.

---

## 1. The box: user, SSH, firewall, updates

```sh
# as root on a fresh Ubuntu 24.04
adduser --disabled-password --gecos "" velorki
usermod -aG sudo velorki
install -d -m 0700 -o velorki -g velorki /home/velorki/.ssh
cp /root/.ssh/authorized_keys /home/velorki/.ssh/authorized_keys
chown velorki:velorki /home/velorki/.ssh/authorized_keys
chmod 600 /home/velorki/.ssh/authorized_keys
```

SSH hardening — `/etc/ssh/sshd_config.d/99-velorki.conf`:

```sh
cat >/etc/ssh/sshd_config.d/99-velorki.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
X11Forwarding no
AllowUsers velorki
EOF
sshd -t && systemctl restart ssh
```

Keep a second terminal open until you have logged in as `velorki` once.

Firewall. 443 is opened per Cloudflare range in step 3; nothing else is public.

```sh
ufw default deny incoming
ufw default allow outgoing
ufw allow from <your.ip.addr.ess> to any port 22 proto tcp comment 'admin ssh'
ufw allow from <github.actions.ip> to any port 22 proto tcp comment 'deploy'  # optional, see step 7
ufw --force enable
ufw status verbose
```

GitHub-hosted runners have no fixed address. Either leave 22 open to the
world (key-only auth, forced command — see step 7) or run the deploy from a
self-hosted runner or your own machine. Leaving it open is the normal choice:

```sh
ufw allow 22/tcp comment 'ssh'
```

Unattended upgrades:

```sh
apt update && apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades       # answer yes
systemctl status unattended-upgrades --no-pager
```

## 2. Node 22 LTS and the orkify CLI

First, is it already there? Any system-wide Node 22.13 or newer will do — that
is where `node:sqlite` is unflagged — and on a shared box there usually is one:

```sh
node -v          # 22.13+ → skip the install below entirely
```

Otherwise NodeSource, because it gives a system-wide Node that a systemd unit
and cron can both see (mise would need per-user shims):

```sh
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node -v          # v22.x — `node:sqlite` is unflagged from 22.13
```

```sh
sudo npm i -g @orkify/cli
orkify --version
```

Boot persistence. `orkify autostart` installs the systemd template shipped with
the package (`$(npm root -g)/orkify/boot/systemd/[email protected]`); the unit
calls `orkify restore` on start and `orkify kill` on stop, and loads
`/etc/orkify/env` if it exists.

```sh
sudo orkify autostart          # run as the user that will own the processes
sudo install -d -m 0755 /etc/orkify
sudo install -m 0600 /dev/null /etc/orkify/env     # optional; see step 6
```

"As the user that will own the processes" is the whole point on a shared box:
the unit is per user, so running this as `velorki` gives `velorki`'s cluster its
own unit beside the one another user (`orkify`, say) already has, and the two
restart independently. `/etc/orkify/env` is loaded by *every* such unit, so on a
shared box put Velorki's variables in `/etc/velorki/web.env` instead (step 6).

The process list is snapshotted to `~/.orkify/snapshot.yml`; logs go to
`~/.orkify/logs/velorki-web.stdout.log` and `.stderr.log`, rotated at 100 MB,
90 files, 90 days by default.
(<https://orkify.com/docs/cli>)

## 3. Directories, sqlite3, cron

```sh
sudo install -d -o velorki -g velorki -m 0755 /srv/velorki            # releases
sudo install -d -o velorki -g velorki -m 0750 /srv/velorki/incoming   # artefacts
sudo install -d -o velorki -g velorki -m 0700 /var/lib/velorki        # share.sqlite
sudo install -d -o velorki -g velorki -m 0700 /var/backups/velorki
sudo install -d -o caddy -g caddy -m 0755 /var/log/caddy      # step 4a only
sudo apt install -y sqlite3
```

The `/var/log/caddy` line is for step 4a. With nginx (4b) the access logs go to
`/var/log/nginx/`, which the package already owns.

`/var/lib/velorki` is deliberately outside the release tree: Orkify unpacks
each release into its own directory, so a relative `SHARE_DB_PATH` would break
every share link already handed out.

The directory stays `0700`. The database file inside it does not need a
`chmod` here: the app sets `share.sqlite` and its `-wal` and `-shm` siblings to
`0600` itself every time it opens them, so a stray umask cannot leave a rider's
GPX world-readable.

Install the server-side scripts and the two cron entries. Clone the repo
somewhere on the box (or `scp` the files over) and, from that checkout:

```sh
# the Cloudflare range refresher: ONE of these two, matching the proxy
sudo install -m 0755 deploy/web/cloudflare-ips.sh       /usr/local/bin/velorki-cloudflare-ips        # 4a, Caddy
sudo install -m 0755 deploy/web/cloudflare-ips-nginx.sh /usr/local/bin/velorki-cloudflare-ips-nginx  # 4b, nginx

sudo install -m 0755 deploy/web/backup-sqlite.sh  /usr/local/bin/velorki-backup-sqlite
sudo install -m 0755 deploy/web/velorki-deploy    /usr/local/bin/velorki-deploy

cat <<'EOF' | sudo tee /etc/cron.d/velorki
# m h dom mon dow user command
17 4 * * * root    /usr/local/bin/velorki-cloudflare-ips >>/var/log/velorki-cloudflare-ips.log 2>&1
23 3 * * * velorki /usr/local/bin/velorki-backup-sqlite  >>/var/log/velorki-backup.log 2>&1
EOF
```

With nginx, the first cron line names `velorki-cloudflare-ips-nginx` instead.
The two scripts do the same fetch and the same validation and differ in what
they write and what they refuse to do:

| | 4a `cloudflare-ips.sh` | 4b `cloudflare-ips-nginx.sh` |
|---|---|---|
| Writes | `/etc/caddy/cloudflare-ips.caddy` (one `trusted_proxies static` line) | `/etc/nginx/conf.d/cloudflare-real-ip.conf` (`set_real_ip_from` per range, `real_ip_header CF-Connecting-IP`, `real_ip_recursive on`) |
| Firewall | adds and removes its own `ufw` rules for 443 | **touches nothing**; prints the `ufw allow` lines for the operator |
| Validates | `caddy validate` before reloading | `nginx -t`, and puts the previous file back if it fails |
| Reload | `systemctl reload caddy`, only on change | `systemctl reload nginx`, only on change |

`velorki-backup-sqlite` runs `sqlite3 .backup`, checks `PRAGMA integrity_check`
on the copy, gzips it into `/var/backups/velorki/share-<date>.sqlite.gz` and
deletes anything older than 30 days. `cp` is not a substitute: the database runs
in WAL mode with two writers.

## 4. The Origin CA certificate and the proxy

The certificate is the same either way. The proxy is a choice: **4a** installs
Caddy, which is right on a box that is only Velorki's; **4b** adds a server
block to the nginx that is already running, which is right on a box that serves
something else — two proxies cannot both hold 443.

```sh
ss -ltnp | grep -E ':(80|443|8080) '     # is anything already on 80/443?
systemctl is-active nginx caddy          # and is it one of these two?
```

**The certificate.** Cloudflare dashboard → the `velorki.com` zone → SSL/TLS →
Origin Server → Origin Certificates → **Create Certificate**. Let Cloudflare
generate the private key and CSR (RSA or ECC), hostnames:

```
velorki.com
*.velorki.com
```

A wildcard covers one label, so `*.velorki.com` covers `www` and `api` but not
`a.b.velorki.com`. Validity: **15 years**, the longest option in the dropdown.
You get two blobs; the private key is shown once.
(<https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/>)

This certificate is trusted by Cloudflare only. A direct browser hit on the
origin shows a certificate error — that is the design; nothing but Cloudflare
may reach the box anyway. **One certificate per domain:** it is issued from the
`velorki.com` zone and covers that zone's names, so on a shared box the other
site keeps the certificate it already has, in its own directory. Where Velorki's
two files land is the only difference — `/etc/caddy/certs/` in 4a,
`/etc/ssl/velorki/` in 4b.

### 4a. Caddy (fresh box)

```sh
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

(<https://caddyserver.com/docs/install#debian-ubuntu-raspbian>)

```sh
sudo install -d -m 0755 /etc/caddy/certs
sudo install -m 0644 /dev/null /etc/caddy/certs/velorki.com.pem
sudo install -m 0640 -g caddy /dev/null /etc/caddy/certs/velorki.com.key
sudo nano /etc/caddy/certs/velorki.com.pem      # paste the certificate
sudo nano /etc/caddy/certs/velorki.com.key      # paste the private key
sudo chown root:caddy /etc/caddy/certs/velorki.com.*
```

Config, and the Cloudflare range snippet it imports:

```sh
sudo install -m 0644 deploy/web/Caddyfile /etc/caddy/Caddyfile
sudo /usr/local/bin/velorki-cloudflare-ips        # writes /etc/caddy/cloudflare-ips.caddy + ufw rules
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
```

The Caddyfile's `servers` block sets `trusted_proxies static <ranges>`,
`client_ip_headers CF-Connecting-IP` and `trusted_proxies_strict`, so the
client address the app rate-limits on comes from Cloudflare's header and only
from a connection that really came from Cloudflare.
(<https://caddyserver.com/docs/caddyfile/options>)

### 4b. nginx (a box that already has one)

`deploy/web/velorki.nginx.conf` is a `sites-available` file with four server
blocks: one `:80` that 301s (harmless behind Cloudflare, which is told to always
use HTTPS, but a plain request that does arrive should not be a reset), and one
`:443` each for the apex, `www` (308 to the apex) and the api host. Every
directive in it is inside a server block, so the site already on this nginx
keeps its own settings.

The one file that is global is the generated
`/etc/nginx/conf.d/cloudflare-real-ip.conf`: Debian and Ubuntu glob `conf.d/*.conf`
into the `http` block, so `real_ip_header CF-Connecting-IP` applies to the other
site too — but only to requests whose peer address is in a Cloudflare range, so
it either does exactly the same good thing there or nothing at all. If the
neighbour must not see it, put the file somewhere nginx does not glob and let the
server blocks be the only thing that includes it:

```sh
sudo SNIPPET=/etc/nginx/snippets/cloudflare-real-ip.conf \
  /usr/local/bin/velorki-cloudflare-ips-nginx
# then change the three `include` lines in the server blocks to match
```

The certificate, in its own directory rather than nginx's, so it is obviously
not the other site's:

```sh
sudo install -d -m 0755 /etc/ssl/velorki
sudo install -m 0644 /dev/null /etc/ssl/velorki/velorki.com.pem
sudo install -m 0600 /dev/null /etc/ssl/velorki/velorki.com.key
sudo nano /etc/ssl/velorki/velorki.com.pem      # paste the certificate
sudo nano /etc/ssl/velorki/velorki.com.key      # paste the private key
```

nginx's master process reads both as root before dropping privileges, so the key
stays `0600 root:root`; no group needs it.

**The Cloudflare ranges first.** The server blocks `include`
`/etc/nginx/conf.d/cloudflare-real-ip.conf`, so `nginx -t` fails while that file
does not exist. Generate it before enabling the site:

```sh
sudo /usr/local/bin/velorki-cloudflare-ips-nginx
```

It writes one `set_real_ip_from <cidr>;` per published Cloudflare range plus
`real_ip_header CF-Connecting-IP;` and `real_ip_recursive on;`, which is nginx's
half of the same arrangement Caddy's `trusted_proxies` makes: `$remote_addr`
becomes the real visitor, and only for a connection that came from Cloudflare.
It prints the matching `ufw` rules and applies none of them — the firewall is
shared with the other site.
(<https://nginx.org/en/docs/http/ngx_http_realip_module.html>)

Then the site:

```sh
sudo install -m 0644 deploy/web/velorki.nginx.conf /etc/nginx/sites-available/velorki
sudo ln -sfn /etc/nginx/sites-available/velorki /etc/nginx/sites-enabled/velorki
sudo nginx -t
sudo systemctl reload nginx        # reload, not restart: the other site keeps serving
```

Read the file before reloading — it carries the reasoning for every directive.
The four that matter:

- `proxy_set_header Host $host` — load-bearing. nginx's default upstream `Host`
  is `$proxy_host`, i.e. `127.0.0.1:8080`, which the app's host gate reads as
  the *api* role (that is how Orkify's header-less health probe reaches
  `/health`). Without this line the site is unreachable and the relay answers on
  every hostname.
  (<https://nginx.org/en/docs/http/ngx_http_proxy_module.html>)
- `proxy_http_version 1.1` — nginx talks HTTP/1.0 upstream by default on
  anything before 1.29.7, and 1.0 has neither chunked framing nor keep-alive.
- On the api host, `proxy_buffering off`, `proxy_cache off`,
  `proxy_read_timeout 3600s` and `chunked_transfer_encoding on` — `POST /ai/plan`
  is an SSE stream that runs for minutes. The defaults would hold it in 4–8 KB
  buffers and release it in lumps, and 60 s is the default read timeout.
- `client_max_body_size 4m` on the api host, a ceiling in front of the app's own
  limits (1 MB default, 3 MB for `POST /share`), so nginx answers 413 before a
  byte reaches Node.

`CF-Connecting-IP` passes through untouched — nginx does not strip unknown
request headers — and the config re-emits it as `$remote_addr`, the value
`real_ip` has already vouched for. That is what the app reads:
`CLIENT_IP_HEADER=cf-connecting-ip` with `TRUST_PROXY=1` (step 6), so nginx must
not strip or rename it. Drop it and the app falls back to the left-most
`X-Forwarded-For`, which this config also sets to `$remote_addr`, so it degrades
quietly rather than breaking; lose both and every caller shares the key
`"unknown"` — one rate-limit bucket for the whole internet.

**HTTP/2 on a shared socket.** `listen ... http2` is a property of the listening
socket, not of one server block, and nginx deprecates it in favour of a
per-server `http2 on;` (1.25.1+; stock Ubuntu 24.04 has 1.24, which does not
know that directive). Check what the neighbour does before reloading, or nginx
logs `protocol options redefined for 0.0.0.0:443` and the first block read
decides HTTP/2 for both sites:

```sh
nginx -v
grep -rn 'listen.*443' /etc/nginx/sites-enabled/
```

(<https://nginx.org/en/docs/http/ngx_http_v2_module.html>)

**No cache or security headers in nginx.** Next.js sends the whole security
header set itself (`web/next.config.ts`) and answers `/_next/static/*` with
`cache-control: public, max-age=31536000, immutable`. An `expires max` or an
`add_header` here would overwrite an identical value or emit a second copy, so
the config deliberately has neither.

## 5. Cloudflare

**Nameservers.** Add the site in the Cloudflare dashboard, then replace the
nameservers at the registrar with the two Cloudflare gives you. Propagation is
minutes to a few hours.

**DNS.** All three records proxied (orange cloud):

| Type | Name  | Content        | Proxy |
|------|-------|----------------|-------|
| A    | `@`   | `<VPS IPv4>`   | on    |
| AAAA | `@`   | `<VPS IPv6>`   | on    |
| A    | `www` | `<VPS IPv4>`   | on    |
| AAAA | `www` | `<VPS IPv6>`   | on    |
| A    | `api` | `<VPS IPv4>`   | on    |
| AAAA | `api` | `<VPS IPv6>`   | on    |

Skip the AAAA rows if the VPS has no IPv6.

**SSL/TLS.**

- Encryption mode: **Full (strict)** (SSL/TLS → Overview). Requires the Origin
  CA certificate from step 4.
- **Always Use HTTPS**: on (SSL/TLS → Edge Certificates).
- **Minimum TLS Version**: 1.2.
- **HSTS**: enable only after the site works end to end, both hostnames, for at
  least a day. Start `max-age` at 6 months, no preload until you are sure the
  domain will never serve plain HTTP again.

**Authenticated Origin Pulls** (optional, recommended). Makes Cloudflare present
a client certificate so the origin refuses anyone else even if the ranges leak:

```sh
# 4a
sudo curl -fsSL https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o /etc/caddy/certs/cloudflare-origin-pull-ca.pem
# 4b
sudo curl -fsSL https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o /etc/ssl/velorki/cloudflare-origin-pull-ca.pem
```

Turn it on in SSL/TLS → Origin Server → Authenticated Origin Pulls (the
zone-wide toggle) **first**, then add to each site's `tls` directive in
`/etc/caddy/Caddyfile`:

```caddyfile
tls /etc/caddy/certs/velorki.com.pem /etc/caddy/certs/velorki.com.key {
	client_auth {
		mode require_and_verify
		trust_pool file /etc/caddy/certs/cloudflare-origin-pull-ca.pem
	}
}
```

and `sudo systemctl reload caddy`. The commented block at the bottom of
`deploy/web/Caddyfile` is the same thing.

With nginx it is two lines in each of the three `:443` server blocks — both are
per server, so the other site on the box is unaffected — then `nginx -t` and
`systemctl reload nginx`. The commented block at the bottom of
`deploy/web/velorki.nginx.conf` is the same thing:

```nginx
ssl_client_certificate /etc/ssl/velorki/cloudflare-origin-pull-ca.pem;
ssl_verify_client on;
```
(<https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/set-up/global/>,
<https://caddyserver.com/docs/caddyfile/directives/tls>)

**Cache Rules** (Caching → Cache Rules). One rule, first in the list:

- Name: `api bypass`
- If: `Hostname` equals `api.velorki.com`
- Then: **Bypass cache**

The relay sends `cache-control: no-store` on every response that does not bring
a policy of its own - `POST /ai/plan` keeps the `no-cache, no-transform` an
event stream needs - and this makes sure no future Cloudflare default ever
caches a token exchange or buffers a stream.

**Do not enable Cache Everything for `velorki.com`.** The site negotiates the
language of an unprefixed path from `Accept-Language` and the `NEXT_LOCALE`
cookie - `/` is the English page for one visitor and a redirect to `/de` for
another - and Cloudflare ignores `Vary` on everything but `Accept-Encoding`, so
a cached `/` would pin every visitor to whichever language was asked for first.
The static assets under `/_next/static/` are already cached by their own
immutable headers and need no rule.

**Speed → Optimization.** Turn **Rocket Loader** off and **Email Obfuscation**
off. Both rewrite the HTML and inject a script, which the site's CSP
(`script-src 'self' 'unsafe-inline'`, no third-party origin) blocks — the page
then loads without its JavaScript.

**Security → Bots.** **Bot Fight Mode** off, or excluded for
`api.velorki.com`. The mobile app is exactly the kind of non-browser client it
challenges, and a challenge page is not a JSON error the app can handle. Rate
limiting stays in the app, so the limits are the same with or without the edge.

**Server-Sent Events.** `POST /ai/plan` streams through Cloudflare fine, but a
connection that sends nothing for 100 seconds is dropped (error 524). The app
writes a `: ping` comment every 20 s, which keeps it open; do not remove it, and
do not add a proxy in front that buffers. Both configs are set up not to: Caddy
with `flush_interval -1`, nginx with `proxy_buffering off` on the api host.

## 6. First deploy

`orkify deploy local` unpacks the artefact, runs `deploy.install` and
`deploy.build` from `web/orkify.yml` **on the server**, then starts or
rolling-reloads the process. So the box needs enough RAM for `next build` —
2 GB is tight, 4 GB is comfortable.

Build the artefact from a checkout (your machine or CI):

```sh
cd web
npm ci
npx orkify deploy pack . --output ../velorki-web.tar.gz
```

Ship and deploy:

```sh
scp velorki-web.tar.gz velorki@<host>:/srv/velorki/incoming/
ssh velorki@<host>
cd /srv/velorki
orkify deploy local /srv/velorki/incoming/velorki-web.tar.gz
```

(Once the forced-command key from step 7 is installed, `scp` to that key is
blocked; use the workflow, or your own admin key.)

**Configuration.** Two supported homes, in this order of preference:

1. **Orkify dashboard → Settings → Secrets**, scoped to the project. The agent
   injects them into the managed processes on its next heartbeat and they take
   precedence over the `env:` block in `orkify.yml`. Changing one and restarting
   the process is enough. (<https://orkify.com/docs/secrets>)
2. **A file on the box.** `/etc/orkify/env` (0600) is loaded by the systemd unit
   `orkify autostart` installed, for every managed process. For a file scoped to
   this app only, put it at `/etc/velorki/web.env` (0600, owned by `velorki`)
   and add to the process in `web/orkify.yml`:

   ```yaml
       nodeArgs: ['--env-file=/etc/velorki/web.env']
   ```

`deploy/web/velorki-web.env.example` is the complete list with comments. The
values that must be right on the first boot: `API_HOST`, `SITE_HOST`,
`PUBLIC_BASE_URL`, `NEXT_PUBLIC_SITE_URL`, `CLIENT_IP_HEADER`, `TRUST_PROXY`,
`COUNTERS`, `SHARE_DB_PATH`, and `REVENUECAT_MODE` (it defaults to `live`, so
set it explicitly to `stub` until RevenueCat exists, or every authenticated
route answers 503).

**The health check.** `web/orkify.yml` sets `healthCheck: /health`. Orkify
probes `http://localhost:8080/health`, three attempts one second apart, and a
non-2xx marks the worker failed — that gates every start and every rolling
reload. (<https://orkify.com/docs/cli>) The probe dials loopback and cannot send
headers, so it arrives with `Host: localhost:8080`; the app's host gate treats a
loopback Host (`localhost:<port>`, `127.0.0.1:<port>`, `[::1]:<port>`) as the
API role for exactly that reason. On the box:

```sh
curl -s http://127.0.0.1:8080/health | head -c 200      # the relay's JSON
curl -s -H 'Host: velorki.com' http://127.0.0.1:8080/ | head -c 200   # a site page
```

A site page needs the explicit `Host:` header; without one you get the API role.

Check it came up:

```sh
orkify list                      # velorki-web, 2 workers, online
orkify logs velorki-web -f
```

## 7. Deploys from GitHub

`.github/workflows/web-deploy.yml` runs on a `web-v*` tag in the `release`
environment (maintainer approval), after `web.yml`'s checks, and streams the
artefact into the forced command.

Secrets on the `release` environment:

| Secret | What |
|---|---|
| `DEPLOY_SSH_KEY` | the private half of a dedicated ed25519 key, deploy-only |
| `DEPLOY_HOST` | the VPS hostname or address |
| `DEPLOY_HOST_KEY` | `ssh-keyscan -t ed25519 <host>` output, verbatim |
| `DEPLOY_USER` | `velorki` |

```sh
ssh-keygen -t ed25519 -f ~/.ssh/velorki-deploy -C deploy@github -N ''
ssh-keyscan -t ed25519 <host>          # paste the output into DEPLOY_HOST_KEY
```

On the box, in `/home/velorki/.ssh/authorized_keys`, one line:

```
command="/usr/local/bin/velorki-deploy",restrict ssh-ed25519 AAAA...  deploy@github
```

`restrict` turns off port, agent and X11 forwarding, pty allocation and
`~/.ssh/rc`. Whatever the client asks for lands in `SSH_ORIGINAL_COMMAND` and
the script ignores everything except the arguments — it accepts only

```
velorki-deploy <name>.tar.gz <sha256>        # tarball on stdin, then deploy
velorki-deploy deploy /srv/velorki/incoming/<name>.tar.gz   # redeploy, rollback
```

rejects shell metacharacters, refuses any path that does not resolve inside
`/srv/velorki/incoming`, and verifies the sha256 before `orkify deploy local`
sees the file. A forced command also blocks `scp` and `sftp`, which is why the
artefact travels on stdin rather than as a separate copy step.

Release:

```sh
git tag web-v1.0.0 && git push origin web-v1.0.0
# approve the run in the Actions tab
```

## 8. Verification

```sh
# both hostnames, through Cloudflare
curl -sI https://velorki.com/            | head -5     # 200, cf-ray present
curl -sI https://www.velorki.com/        | head -5     # 308 → https://velorki.com/
curl -s  https://api.velorki.com/health  | jq .        # {"status":"ok", version, brouter, llm}
curl -s  https://velorki.com/health      -o /dev/null -w '%{http_code}\n'   # 404, HTML
curl -s  https://api.velorki.com/        -o /dev/null -w '%{http_code}\n'   # 404, JSON
curl -s  https://velorki.com/s/nope.gpx  | jq .        # {"error":{"code":"not_found",...}}
curl -s  https://velorki.com/robots.txt
curl -sI https://velorki.com/            | grep -i content-security-policy
```

On the box, straight to the app. Proxy-independent: these two skip whatever
terminates TLS and prove the app itself is up and that its host gate works.

```sh
curl -s http://127.0.0.1:8080/health
curl -s -H 'Host: velorki.com' -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
```

Then the proxy, still without Cloudflare. `--resolve` pins the public name to
the loopback address so SNI and `Host` are the real ones, and `-k` accepts the
Origin CA certificate that no local trust store knows:

```sh
curl -sk --resolve velorki.com:443:127.0.0.1 https://velorki.com/ \
  -o /dev/null -w '%{http_code} HTTP/%{http_version}\n'                  # 200 HTTP/2
curl -sk --resolve www.velorki.com:443:127.0.0.1 https://www.velorki.com/ \
  -o /dev/null -w '%{http_code} %{redirect_url}\n'                       # 308 https://velorki.com/
curl -sk --resolve api.velorki.com:443:127.0.0.1 https://api.velorki.com/health | jq .
curl -sI -H 'Host: velorki.com' http://127.0.0.1/ | head -3              # 301 to https
```

A 502 from those means the proxy is up and the app is not; a certificate error
other than the expected untrusted-issuer one means the wrong `.pem` is
installed; a 404 with a JSON body on the *site* host means `Host` is not being
forwarded.

Which proxy answered, and whether it is happy:

```sh
systemctl is-active nginx caddy
sudo nginx -t                                   # 4b
sudo tail -n 20 /var/log/nginx/velorki-api.error.log   # 4b
sudo journalctl -u caddy -n 20 --no-pager       # 4a
```

SSE past Cloudflare's 100 s idle limit — this must run for minutes and keep
printing:

```sh
curl -N -sS https://api.velorki.com/ai/plan \
  -H 'Authorization: Bearer <app_user_id>' \
  -H 'X-AI-Consent: 1' \
  -H 'Content-Type: application/json' \
  -d '{"step":"plan","prompt":"60 km loop from here, mostly gravel"}'
```

If it arrives in lumps rather than line by line, run the same command on the box
with `-k --resolve api.velorki.com:443:127.0.0.1`: streaming there and lumpy
through Cloudflare is an edge problem, lumpy in both places is the proxy
(`proxy_buffering off` missing, or `gzip` on this host).

Rate limit across both workers — the 11th request inside a minute must be 429
with `Retry-After`, no matter which worker answers it:

```sh
for i in $(seq 1 11); do
  curl -s -o /dev/null -w "%{http_code} " https://api.velorki.com/oauth/strava/token \
    -H 'Authorization: Bearer <app_user_id>' -H 'Content-Type: application/json' \
    -d '{"code":"x","redirect_uri":"velorki://oauth/strava"}'
done; echo
# 502 502 ... 429
```

The 502s are the point: Strava is configured, so the relay really does call it
and really is rejected for the fake `code`, which is `upstream_error` - and a
request has to get that far to be counted, so the 11th inside the minute is the
`429`. A run of 503s instead means Strava is not configured on this box and the
limiter was never reached.

From the phone: create a share link, open `https://velorki.com/s/<id>` in the
browser, download the GPX, and tap "Open in Velorki" — it must import.

Finally `orkify list` shows `velorki-web` with **2** workers online, and
`orkify logs velorki-web -n 50` shows one boot line per worker and no restarts.

## 9. Operations

| Task | Command |
|---|---|
| Rolling restart, no downtime | `orkify reload velorki-web` |
| Hard restart | `orkify restart velorki-web` |
| Status | `orkify list` |
| Logs | `orkify logs velorki-web -f` (`--err`, `-n 200`) |
| Redeploy a previous artefact | `orkify deploy local /srv/velorki/incoming/velorki-web-<sha>.tar.gz` |
| Refresh Cloudflare ranges now | `sudo /usr/local/bin/velorki-cloudflare-ips` (4a) / `…-ips-nginx` (4b) |
| Back up now | `sudo -u velorki /usr/local/bin/velorki-backup-sqlite` |
| Reload the proxy after a config change | `sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy` (4a) / `sudo nginx -t && sudo systemctl reload nginx` (4b) |

**Rollback.** Orkify keeps the previous release on disk and rolls back by itself
if a worker crashes inside `crashWindow` (30 s). For a bad release that does not
crash, re-run `orkify deploy local` with the previous artefact from
`/srv/velorki/incoming` (the deploy script keeps the last five), or push the
previous tag again. The database is outside the release tree and schema changes
are additive, so a rollback never needs a database restore.

**Logs.** Orkify rotates its own (`~/.orkify/logs/`, 100 MB / 90 files /
90 days; tune with `logMaxSize`, `logMaxFiles`, `logMaxAge` in `orkify.yml`).
Caddy's access log rotates through the `roll_*` options in the Caddyfile
(50 MiB, 10 files, 30 days). nginx's do not rotate themselves, but the four
`velorki-*.log` files the server blocks write live in `/var/log/nginx/`, which
the distribution's own logrotate rule already globs — nothing to add. The two
cron scripts append to `/var/log/velorki-*.log` — add *those* to logrotate if
they ever matter.

**Updating Node.** Minor releases come from `apt` with the NodeSource repo. For
a major: install it, `orkify reload velorki-web`, check `orkify list`, and keep
`engines.node` in `web/package.json` and the `node-version` in `web.yml` and
`web-deploy.yml` in step with it.

**Restoring the database.**

```sh
orkify down velorki-web
sudo -u velorki gunzip -c /var/backups/velorki/share-2026-09-17.sqlite.gz \
  > /var/lib/velorki/share.sqlite
sudo -u velorki rm -f /var/lib/velorki/share.sqlite-wal /var/lib/velorki/share.sqlite-shm
sudo -u velorki sqlite3 /var/lib/velorki/share.sqlite 'PRAGMA integrity_check;'
orkify restore              # or: orkify deploy local <last artefact>
```

**What to back up.** Three things are not reproducible from this repository:

1. `/var/lib/velorki/share.sqlite` — the share links (the nightly job).
2. The environment: the Orkify dashboard secrets, or `/etc/velorki/web.env` /
   `/etc/orkify/env`.
3. The Origin CA certificate and its private key —
   `/etc/caddy/certs/velorki.com.{pem,key}` in 4a,
   `/etc/ssl/velorki/velorki.com.{pem,key}` in 4b. The key is shown once at
   issue time; losing it means issuing a new certificate (free, and no rate
   limit, but it is downtime).

Everything else — the release tree, the proxy config, the cron scripts — comes
back from a checkout and this file.

## 10. Running it locally

`web/README.md`. In short: `npm run dev` with a `.env.local`
(`REVENUECAT_MODE=stub`, `COUNTERS=memory`, `SHARE_DB_PATH=./data/share.sqlite`,
`DEV_HOSTS=1` so one `localhost:3000` serves both roles), and
`npm run build && npm run start:cluster` for the cluster.

`start:cluster` is deliberately the same shape as the VPS: two workers, the
`/health` readiness probe, the 15 s kill timeout, and `PORT=8080` so it listens
where `web/orkify.yml` says the process listens. What it is *not* is a copy of
the deploy - Orkify reads `orkify.yml` there and adds `crashWindow`, the rolling
reload and the dashboard secrets, none of which a bare `orkify run` has. It is
for watching the two workers share a rate-limit window, not for rehearsing a
release.

---

## Verified against the vendors' documentation

| Fact | Source |
|---|---|
| `orkify.yml` schema: `version`, `deploy.{install,build,crashWindow,buildEnv,sourcemaps}`, `processes[].{name,script,cwd,execMode,workerCount,port,healthCheck,killTimeout,env,nodeArgs,...}` | <https://orkify.com/docs/cli> |
| Health probe is `http://localhost:{port}{healthCheck}`, 3 retries 1 s apart, 2xx = ready; skipped if `port` is unset. No headers can be added | <https://orkify.com/docs/cli> |
| `orkify deploy local <tarball>` extracts, runs install/build, reconciles processes, keeps the previous release and auto-rolls-back on a crash inside the window | <https://orkify.com/docs/cli>, <https://orkify.com/docs/deployments> |
| `orkify reload` is a rolling restart with at least one worker always serving | <https://orkify.com/docs/cli> |
| `orkify autostart` uses a systemd template from `$(npm root -g)/orkify/boot/systemd/`, calls `orkify restore`, loads `/etc/orkify/env` | <https://orkify.com/docs/cli> |
| Logs in `~/.orkify/logs/{process}.std{out,err}.log`, defaults 100 MB / 90 files / 90 days | <https://orkify.com/docs/cli> |
| `ORKIFY_WORKER_ID`, `ORKIFY_WORKERS`, `ORKIFY_CLUSTER_MODE` are set on every managed process (the share sweeper uses worker 0) | <https://orkify.com/docs/cli> |
| Dashboard secrets are per project, injected at runtime on the agent's next heartbeat, and take precedence over the config's `env` block | <https://orkify.com/docs/secrets> |
| Next.js needs `output: 'standalone'`, `public/` and `.next/static` copied in by hand, Node 22+, Next 16+ for `use cache`; `@orkify/next/use-cache` and `@orkify/next/isr-cache` are the two handlers | <https://orkify.com/docs/nextjs> |
| `@orkify/cache`: `incr/get/set/getAsync`, cluster writes broadcast over IPC, eventually consistent, degrades to a local cache outside a cluster | <https://orkify.com/docs/cache> |
| Origin CA: SSL/TLS → Origin Server → Origin Certificates → Create Certificate; up to 200 SANs; a wildcard covers one label; then switch to Full (strict) | <https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/> |
| Global Authenticated Origin Pulls CA: `https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem`, enabled zone-wide from the dashboard | <https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/set-up/global/> |
| Caddy `trusted_proxies static <ranges>`, `client_ip_headers`, `trusted_proxies_strict` in the `servers` global block | <https://caddyserver.com/docs/caddyfile/options> |
| Caddy `client_auth { mode require_and_verify; trust_pool file <pem> }` (the old `trusted_ca_cert_file` is gone) | <https://caddyserver.com/docs/caddyfile/directives/tls> |
| Cloudflare's published ranges: `https://www.cloudflare.com/ips-v4`, `https://www.cloudflare.com/ips-v6` | <https://www.cloudflare.com/ips/> |
| nginx `set_real_ip_from`, `real_ip_header` (default `X-Real-IP`) and `real_ip_recursive` (default `off`) are all valid in `http`, `server` and `location` — so the generated file works both as a `conf.d` drop-in and as a per-server `include` | <https://nginx.org/en/docs/http/ngx_http_realip_module.html> |
| nginx upstream defaults that the api host has to override: `proxy_buffering on`, `proxy_read_timeout 60s`, `proxy_send_timeout 60s`, `proxy_cache off`, and `proxy_http_version` 1.0 before nginx 1.29.7. `Host` defaults to `$proxy_host`, and the module itself recommends `$host` instead | <https://nginx.org/en/docs/http/ngx_http_proxy_module.html> |
| nginx `client_max_body_size` defaults to `1m` and `chunked_transfer_encoding` to `on`; `listen ... http2` is deprecated in favour of the `http2` directive | <https://nginx.org/en/docs/http/ngx_http_core_module.html> |
| The `http2 on;` directive is `http`/`server` context and exists only from nginx 1.25.1 | <https://nginx.org/en/docs/http/ngx_http_v2_module.html> |

**Not verified — check on the box before relying on it:**

- `deploy/web/velorki.nginx.conf` has never been through `nginx -t`: it was
  written on a machine with no nginx, and checked only for balanced braces,
  no tabs and terminated statements. Step 4b's `sudo nginx -t` is the first
  real test; run it before the reload, not after.
- Which nginx version the box has, and therefore whether `listen 443 ssl http2`
  or `listen 443 ssl` + `http2 on;` is the right spelling, and what the site
  already on it uses. `nginx -v` and
  `grep -rn 'listen.*443' /etc/nginx/sites-enabled/` settle both.

**Not verified — check in the Orkify docs before relying on it:**

- The exact spelling of `orkify deploy pack`'s `--output` flag. The CLI
  reference names the flag but not its syntax; `orkify deploy pack --help` on
  the box is the authority.
- What `orkify deploy pack` includes and excludes (whether it honours
  `.gitignore`, and whether `node_modules/` and `.next/` are left out). The
  workflow assumes a source artefact that the server installs and builds.
- Where `orkify deploy local` puts the unpacked releases and what the previous
  release directory is called. "Keeps the previous release on disk" is
  documented; the path is not.
- Whether dashboard secrets are present in the environment of the **build**
  step (`deploy.build`) as well as the running process. `NEXT_DEPLOYMENT_ID` is
  therefore shipped in a `.env.production` written by the deploy workflow
  instead of relying on it.
- Whether Orkify's `port:` also sets `PORT` in the process environment.
  `orkify.yml` sets both to 8080 so it does not matter.
