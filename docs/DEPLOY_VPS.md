# Deploying Paisa to a DigitalOcean VPS (Apache + MySQL)

For a single-tenant pilot on a Linux box you already own, running Apache and MySQL,
with manual deploys triggered over SSH.

## What you actually need

**One account: Firebase.** That is the whole list.

The API refuses to start in production unless `AUTH_MODE=firebase`, so Firebase is
genuinely required. Everything else runs on the droplet you already have:

| Piece | Where it comes from | Cost |
| --- | --- | --- |
| MySQL 8 | Already installed on the droplet | — |
| Node.js 22+ | Installed below | — |
| Apache | Already installed; used as the reverse proxy | — |
| TLS certificate | Let's Encrypt via certbot | free |
| Firebase project | New, Spark (free) tier | free |

**What you do not need yet**, despite `.env.example` listing them:

- **Redis** — the worker exists but nothing enqueues jobs, so it processes nothing.
- **Object storage (S3/Spaces)** — statement import records file metadata and a
  SHA-256 fingerprint; no code uploads file bytes anywhere.

Skip both until the features that need them are built. Setting them up now buys
nothing but a bill.

## If other sites already run on this droplet

Check before you change anything:

```bash
sudo bash /srv/paisa/deploy/bootstrap.sh --check paisa.example.com
```

Read-only. It reports Node version and who it would affect, whether ports 3000/4000
are free, your existing Apache vhosts and which one is the default, your existing
databases, and firewall state. Nothing is modified.

What Paisa shares with your Laravel and React sites, and how conflicts are avoided:

| Shared thing | Risk | How this handles it |
| --- | --- | --- |
| **Node** | Installing Node 22 replaces it system-wide and can break other build tooling | Never upgraded without `--upgrade-node`. Test your Laravel/React builds after |
| **Apache default vhost** | A new vhost sorting first would catch requests meant for other sites | Installed as `zz-paisa.conf`, always last alphabetically |
| **MySQL** | Touching an existing database | Creates only `paisa`; the user's privileges are scoped to that one database |
| **ufw** | Enabling a firewall can lock you out and affect other sites | Never enabled automatically. If already active, only adds 80/443 and closes 3000/4000 |
| **Ports 3000/4000** | Already taken by another app | Reported by `--check`; change `PORT` and the vhost's ProxyPass lines if so |

Two things worth knowing regardless:

- `vinext` ignores `HOST` and binds `0.0.0.0`, so port 3000 is internet-reachable
  unless a firewall closes it. On a shared box you may prefer to close it yourself
  rather than let a script enable ufw.
- `certbot --apache` edits Apache config. It only touches the vhost for the domain
  you pass, but take a config backup first if your other sites' TLS is hand-tuned:
  `sudo cp -r /etc/apache2 /root/apache2-backup-$(date +%F)`

## The short version

**Repeat deploys are one line.** Once the droplet is set up, every future release is:

```bash
cd /srv/paisa && ./deploy/deploy.sh
```

**First-time setup is two lines plus two things only you can do.** Clone the repo,
then run the bootstrap:

```bash
sudo git clone YOUR-REPO-URL /srv/paisa && sudo bash /srv/paisa/deploy/bootstrap.sh paisa.example.com
```

[`bootstrap.sh`](../deploy/bootstrap.sh) installs Node 22, git, Apache modules and
certbot, creates the `paisa` service user, creates the MySQL database and user with a
generated password, writes the env file with your domain and database URL already
filled in, installs both systemd units, configures the Apache vhost, and closes the
firewall. It is idempotent — re-running it never overwrites your env file or touches
an existing database.

It stops short of two things, because it cannot do them for you:

1. **Your Firebase values.** You paste them into `<checkout>/paisa.env`. The dashboard
   compiles `NEXT_PUBLIC_*` values in at build time, so this must happen before the
   build, not after.
2. **TLS.** `certbot` can only issue a certificate once your DNS A record resolves to
   the droplet, which depends on your registrar, not this script.

It prints both as numbered next steps when it finishes, with the exact commands.

The rest of this document explains what bootstrap does, for when you need to debug it
or do a step by hand.

## 1. Firebase

At <https://console.firebase.google.com>:

1. Create a project (e.g. `paisa-prod`).
2. **Authentication → Sign-in method → Email/Password → Enable.**
3. **Do not enable multi-factor authentication.** The dashboard sign-in cannot
   complete a second-factor challenge yet, so enrolling a user locks them out.
4. **Project settings → General → Your apps → Web app.** Register one and copy the
   config values into the `NEXT_PUBLIC_FIREBASE_*` entries in your env file.
5. Copy the **Project ID** into `FIREBASE_PROJECT_ID`.
6. **Authentication → Users → Add user.** Create your own account by hand and copy
   its UID into `SEED_OWNER_FIREBASE_UID`. Do the same for your wife and CA if you
   want them seeded on day one; otherwise invite them from the dashboard later.

The API verifies Firebase ID tokens against Google's public keys, so it needs **no
service-account key**. Nothing secret from Firebase lands on the server.

App Check is optional. Leave `APP_CHECK_MODE=off` to start; turning it on requires a
reCAPTCHA v3 site key and the project number, and a mismatch there locks you out of
your own API.

### Verify Firebase locally first

Prove the project works on your Mac before involving the droplet. A wrong project ID
or a disabled sign-in provider is far easier to diagnose here than behind Apache.

```bash
cp deploy/local-firebase.env.example .env.firebase-local   # gitignored
# fill in the values from the console, then:
set -a; . ./.env.firebase-local; set +a
npm run serve &                       # API in firebase mode, in-memory store, :4000
npm --prefix apps/web run build
# PORT is read by both servers, and the file sets it to the API's 4000.
# The dashboard needs its own port or it will fail with EADDRINUSE.
PORT=3000 npm --prefix apps/web run start
```

Open <http://localhost:3000>. You should get the **sign-in page**; sign in with the
account you created in the console and land on the dashboard with the sample books.

`SEED_OWNER_FIREBASE_UID` is what makes this work: it maps your real Firebase UID onto
the sample owner, so the API recognises you without a database. The same variable is
read by the production seed script, so the value you use here is the one you will use
on the droplet.

What failures mean:

| What you see | Cause |
| --- | --- |
| "Authentication is not configured for this deployment" | `NEXT_PUBLIC_FIREBASE_API_KEY` is wrong or was not set at build time |
| "Email sign-in is not enabled for this Firebase project" | Email/Password provider still disabled in the console |
| Signs in, then "This account is not active in a workspace" | `SEED_OWNER_FIREBASE_UID` does not match the UID in Authentication → Users |
| Dashboard loads without asking you to sign in | `NEXT_PUBLIC_AUTH_MODE` was not `firebase` when the dashboard was built |

## 2. Droplet preparation

```bash
# Node 22+ — the dashboard build fails on Node 20 with a confusing
# "does not provide an export named 'glob'" error.
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs git

# A service account that owns the code and runs both processes.
sudo adduser --system --group --home /srv/paisa paisa
sudo mkdir -p /srv/paisa
sudo chown paisa:paisa /srv/paisa
```

## 3. Database

MySQL is already on the box, so this is just a database and a user:

```sql
CREATE DATABASE paisa CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'paisa'@'127.0.0.1' IDENTIFIED BY 'a-long-random-password';
GRANT ALL PRIVILEGES ON paisa.* TO 'paisa'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Keep MySQL bound to `127.0.0.1` (the default on Ubuntu). Nothing outside the droplet
needs to reach it, and a database of financial records should never be exposed.

### Creating the 20 tables

Leave the database empty. Step 4 runs `prisma:deploy`, which creates every table and
records which migrations it applied, so later schema changes apply cleanly on top.
That is the supported path and the one `deploy/migrate.sh` uses from then on.

If you would rather create the schema by hand — through phpMyAdmin, say —
[`deploy/schema.sql`](../deploy/schema.sql) is generated from those same migrations:

```bash
mysql -u paisa -p paisa < deploy/schema.sql
```

Import it into an **empty** database only. Its last section fills Prisma's
`_prisma_migrations` table; without those rows the next `prisma migrate deploy` would
try to create all 20 tables a second time and fail. If you use this file, skip the
`prisma:deploy` line in step 4 — the schema will already exist.

`deploy/schema.sql` is a generated artifact. Never edit it by hand; run
`npm run build:schema-sql` after adding a migration. CI fails if it is out of date.

The tables, for orientation:

| Group | Tables |
| --- | --- |
| Tenancy | `Workspace`, `UserProfile`, `WorkspaceUser`, `Book`, `BookMembership`, `BookInvitation` |
| Ledger | `Transaction`, `TransactionSource`, `TransactionSplit`, `IngestionEvent`, `FinancialAccount` |
| Classification | `Category`, `CategorizationRule`, `Budget`, `RecurringPlan` |
| Review and trail | `PeriodReview`, `Comment`, `AuditEvent`, `Attachment` |
| Plumbing | `IdempotencyRecord` (makes retried SMS and imports safe) |

## 4. Code and configuration

```bash
sudo -u paisa git clone https://github.com/YOUR-ORG/paisa.git /srv/paisa
sudo -u paisa cp /srv/paisa/deploy/paisa.env.example /srv/paisa/paisa.env
sudo chmod 600 /srv/paisa/paisa.env
sudo -e /srv/paisa/paisa.env      # fill in every blank
```

Set `CORS_ORIGINS` and `NEXT_PUBLIC_API_URL` to the same public URL, e.g.
`https://paisa.example.com`, with no trailing slash.

Then install and build once by hand:

```bash
cd /srv/paisa
sudo -u paisa npm ci --include=dev
sudo -u paisa npm --prefix apps/web ci --include=dev
set -a; . <checkout>/paisa.env; set +a
sudo -u paisa --preserve-env npm --workspace @paisa/api run prisma:generate
sudo -u paisa --preserve-env npm --workspace @paisa/api run prisma:deploy
sudo -u paisa --preserve-env npm --workspace @paisa/api run seed
sudo -u paisa --preserve-env npm --prefix apps/web run build
```

`seed` creates your users, books, memberships, and the editable starter categories.
It writes no sample amounts.

## 5. Services

```bash
sudo cp /srv/paisa/deploy/paisa-api.service /etc/systemd/system/
sudo cp /srv/paisa/deploy/paisa-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now paisa-api paisa-web
sudo systemctl status paisa-api paisa-web
```

Logs: `sudo journalctl -u paisa-api -f`

### Close the ports (required)

The API honours `HOST=127.0.0.1` and stays on loopback. **The dashboard does not** —
`vinext start` ignores `HOST` and always binds `0.0.0.0`, so port 3000 is reachable
at `http://your-droplet-ip:3000`, over plain HTTP, bypassing Apache and your
certificate. A firewall is the fix, and it is not optional:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Apache Full'     # 80 + 443
sudo ufw enable
sudo ufw status                  # 3000 and 4000 must NOT appear
```

Verify from your Mac, not from the droplet:

```bash
curl -m 5 http://YOUR-DROPLET-IP:3000     # must time out or refuse
```

## 6. Apache and TLS

Point a DNS **A record** for your subdomain at the droplet's IP, then:

```bash
sudo cp /srv/paisa/deploy/paisa-apache.conf /etc/apache2/sites-available/paisa.conf
sudo sed -i 's/paisa.example.com/YOUR-SUBDOMAIN/' /etc/apache2/sites-available/paisa.conf
sudo a2enmod proxy proxy_http headers rewrite
sudo a2ensite paisa
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo certbot --apache -d YOUR-SUBDOMAIN
```

The dashboard and the API share one hostname: Apache serves the dashboard and
forwards `/v1`, `/health`, and `/ready` to the API. Because the browser never makes a
cross-origin request, there is no CORS preflight to get wrong — a class of failure
this app has already hit twice in development.

`/docs` is deliberately not proxied. To read the API documentation, tunnel it:

```bash
ssh -L 4000:127.0.0.1:4000 you@your-droplet   # then open http://localhost:4000/docs
```

## 7. Verify

```bash
curl https://YOUR-SUBDOMAIN/health     # {"status":"ok","service":"paisa-api"}
curl https://YOUR-SUBDOMAIN/ready      # datastore: reachable
```

Then open the subdomain in a browser. You should get the **sign-in page**, not the
dashboard — if you land straight on the dashboard, `NEXT_PUBLIC_AUTH_MODE` was not
set to `firebase` when the dashboard was built, and the app is running unauthenticated.
Rebuild before going any further.

## Day-to-day development

You keep working on `main`. CI runs on every push; production updates only when you
say so.

```bash
# on your Mac
git push origin main

# on the droplet, once CI is green
cd /srv/paisa && ./deploy/deploy.sh
```

`deploy.sh` pulls, installs, rebuilds the dashboard, restarts both services, and
health-checks them. It **warns and stops** if the release contains migrations that
have not been applied, rather than silently running new code against an old schema.

When a release does change the schema:

```bash
cd /srv/paisa && ./deploy/migrate.sh    # backs up, verifies the dump, then migrates
./deploy/deploy.sh
```

Backups land in `/var/backups/paisa`. Restore with:

```bash
gunzip < /var/backups/paisa/paisa-TIMESTAMP.sql.gz | mysql -u paisa -p paisa
```

### Keeping local development working

Local development does not need any of the above. With no `DATABASE_URL` the API
falls back to an in-memory store, and `AUTH_MODE=dev` skips Firebase entirely:

```bash
npm run serve    # API on :4000, in-memory data, dev auth
npm run dev      # dashboard on :3000
```

So the loop stays: build locally against throwaway data, push, then deploy when the
change is proven. Nothing you do locally can reach the production database.

### One honest caution

You are running a single environment: your development target and the system holding
your household's real financial records are the same machine. For a personal pilot
that is a reasonable trade, and manual deploys plus backed-up migrations cover most
of the risk. But two habits matter:

- **Take a backup before anything schema-shaped.** `migrate.sh` does it for you;
  don't work around it.
- **Restore a backup at least once**, into a scratch database, before you trust it.
  An untested backup is an assumption.

If the pilot ever grows past your household, the first thing to add is a staging
database — not more features.

## Not wired up yet

Being explicit so nothing here reads as finished when it isn't:

- **Statement import** records a file's name, size, and SHA-256 and dedupes on it.
  The bytes are not stored and nothing parses them into transactions yet.
- **The worker** (`apps/worker`) has handlers for imports, reconciliation,
  notifications, and exports, but they are stubs and no code enqueues jobs.
- **MFA** is unsupported in the web sign-in; leave it disabled in Firebase.
- **Email** is never sent. Invitations produce a link you copy and deliver yourself.
