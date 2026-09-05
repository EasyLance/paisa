#!/usr/bin/env bash
# One-command droplet setup for Paisa. Run once, as root:
#
#     sudo bash /srv/paisa/deploy/bootstrap.sh paisa.example.com
#
# Idempotent: safe to re-run. It never overwrites an existing env file and never
# touches an existing database.
#
# It does everything that can be automated:
#   Node 22, git, Apache modules, certbot, the paisa service user, the MySQL
#   database and user, the env skeleton, both systemd units, the Apache vhost,
#   and the firewall.
#
# It deliberately stops short of two things it cannot know or do for you:
#   1. Your Firebase values (you paste them into /etc/paisa/paisa.env).
#   2. TLS, which needs your DNS A record to resolve to this droplet first.
# It prints both as next steps when it finishes.
set -euo pipefail

DOMAIN=${1:-}
APP_DIR=${APP_DIR:-/srv/paisa}
ENV_FILE=${ENV_FILE:-/etc/paisa/paisa.env}
DB_NAME=${DB_NAME:-paisa}
DB_USER=${DB_USER:-paisa}

die() { echo "Error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[ -n "$DOMAIN" ] || die "Usage: sudo bash $0 your-subdomain.example.com"
[ "$(id -u)" = "0" ] || die "Run with sudo."
[ -d "$APP_DIR/.git" ] || die "$APP_DIR is not a git checkout. Clone the repository there first."
command -v apt-get >/dev/null || die "This script targets Debian/Ubuntu."

step "Installing packages"
export DEBIAN_FRONTEND=noninteractive
NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/' || echo 0)
if [ "${NODE_MAJOR:-0}" -lt 22 ]; then
  echo "    Node ${NODE_MAJOR:-none} found; installing 22.x"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
else
  echo "    Node $(node -v) already present"
fi
apt-get install -y git apache2 certbot python3-certbot-apache mysql-client ufw >/dev/null
command -v mysql >/dev/null || die "No mysql client. Install MySQL server on this droplet first."

step "Creating the paisa service user"
if id paisa >/dev/null 2>&1; then
  echo "    user paisa already exists"
else
  adduser --system --group --home "$APP_DIR" --no-create-home paisa
fi
mkdir -p /etc/paisa /var/backups/paisa
chown -R paisa:paisa "$APP_DIR" /var/backups/paisa

step "Database"
if mysql -e "USE \`$DB_NAME\`" 2>/dev/null; then
  echo "    database $DB_NAME already exists, leaving it alone"
  DB_PASS=""
else
  DB_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  mysql <<SQL
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  echo "    created database $DB_NAME and user $DB_USER"
fi

step "Environment file"
if [ -f "$ENV_FILE" ]; then
  echo "    $ENV_FILE already exists, not overwriting"
else
  [ -n "$DB_PASS" ] || die "$ENV_FILE is missing but the database already exists, so its password is unknown. Write $ENV_FILE by hand from deploy/paisa.env.example."
  sed \
    -e "s|^DATABASE_URL=.*|DATABASE_URL=mysql://$DB_USER:$DB_PASS@127.0.0.1:3306/$DB_NAME|" \
    -e "s|paisa.example.com|$DOMAIN|g" \
    "$APP_DIR/deploy/paisa.env.example" > "$ENV_FILE"
  echo "    wrote $ENV_FILE with a generated database password"
fi
chown paisa:paisa "$ENV_FILE"
chmod 600 "$ENV_FILE"

step "systemd units"
cp "$APP_DIR/deploy/paisa-api.service" "$APP_DIR/deploy/paisa-web.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable paisa-api paisa-web >/dev/null
echo "    installed (not started yet: the dashboard must be built first)"

step "Apache"
sed "s/paisa.example.com/$DOMAIN/g" "$APP_DIR/deploy/paisa-apache.conf" > /etc/apache2/sites-available/paisa.conf
a2enmod proxy proxy_http headers rewrite >/dev/null
a2ensite paisa >/dev/null
apache2ctl configtest
systemctl reload apache2
echo "    vhost installed for $DOMAIN"

step "Firewall"
# vinext ignores HOST and binds 0.0.0.0, so ports 3000/4000 must not be public.
ufw allow OpenSSH >/dev/null
ufw allow 'Apache Full' >/dev/null
ufw --force enable >/dev/null
echo "    only 22, 80 and 443 are open"

cat <<NEXT

============================================================
Bootstrap complete. Two things are left, and both need you.

1. Add your Firebase values:

     sudo -e $ENV_FILE

   Fill in FIREBASE_PROJECT_ID and every NEXT_PUBLIC_FIREBASE_* value,
   plus SEED_OWNER_FIREBASE_UID and SEED_OWNER_EMAIL. The database URL and
   your domain are already filled in.

   The dashboard compiles the NEXT_PUBLIC_* values in at build time, so this
   has to happen before the build in step 2, not after.

2. Create the schema, seed, build and start:

     cd $APP_DIR && sudo -u paisa --preserve-env bash -c 'set -a; . $ENV_FILE; set +a; npm ci && npm --prefix apps/web ci && npm --workspace @paisa/api run prisma:generate && npm --workspace @paisa/api run prisma:deploy && npm --workspace @paisa/api run seed && npm --prefix apps/web run build' && systemctl restart paisa-api paisa-web

3. Then, once your DNS A record for $DOMAIN points at this droplet:

     sudo certbot --apache -d $DOMAIN

From then on, deploying is one line:

     cd $APP_DIR && ./deploy/deploy.sh

============================================================
NEXT
