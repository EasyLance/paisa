#!/usr/bin/env bash
# Droplet setup for Paisa on a SHARED server (Laravel, other sites already live).
#
#   sudo bash /srv/paisa/deploy/bootstrap.sh --check paisa.example.com   # report only
#   sudo bash /srv/paisa/deploy/bootstrap.sh paisa.example.com           # apply
#
# Idempotent. Never overwrites an existing env file, never touches an existing
# database, never enables a firewall that is currently off, and never upgrades a
# system-wide Node without --upgrade-node.
set -euo pipefail

DOMAIN=""; CHECK_ONLY=0; UPGRADE_NODE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --upgrade-node) UPGRADE_NODE=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) DOMAIN="$arg" ;;
  esac
done

APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ENV_FILE=${ENV_FILE:-$APP_DIR/paisa.env}
DB_NAME=${DB_NAME:-paisa}
DB_USER=${DB_USER:-paisa}
# Account the services run as. Defaults to a dedicated "paisa" user, but on a box
# where the checkout already belongs to someone (e.g. /var/www owned by your deploy
# user), set SERVICE_USER to that account so nothing is chowned out from under you.
SERVICE_USER=${SERVICE_USER:-paisa}
API_PORT=4000
WEB_PORT=3000

die() { echo "Error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
warn() { echo "    WARNING: $*"; PROBLEMS=$((PROBLEMS+1)); }
ok() { echo "    ok: $*"; }
PROBLEMS=0

[ -n "$DOMAIN" ] || die "Usage: sudo bash $0 [--check] [--upgrade-node] your-subdomain.example.com"
[ "$(id -u)" = "0" ] || die "Run with sudo."
command -v apt-get >/dev/null || die "This script targets Debian/Ubuntu."

# ---------------------------------------------------------------- preflight
echo "Preflight on a shared server. Nothing is changed during these checks."

step "Node"
NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/' || echo 0)
if [ "${NODE_MAJOR:-0}" -ge 22 ]; then
  ok "node $(node -v) is new enough"
  NEED_NODE=0
elif [ "${NODE_MAJOR:-0}" -gt 0 ]; then
  NEED_NODE=1
  warn "node v$NODE_MAJOR is installed and too old (need 22+).
             Upgrading replaces it SYSTEM-WIDE. If your Laravel tooling or the
             React site's build scripts run on this Node, test them afterwards.
             Re-run with --upgrade-node once you accept that, or install Node 22
             for the paisa user only via nvm and skip this script's node step."
else
  NEED_NODE=1
  ok "no system node; installing 22 is safe"
fi

step "Ports"
for port in $API_PORT $WEB_PORT; do
  if ss -ltnp 2>/dev/null | grep -q ":$port "; then
    warn "port $port is already in use by: $(ss -ltnp 2>/dev/null | grep ":$port " | sed 's/.*users:((//;s/).*//' | head -1)
             Paisa needs it. Free it, or change PORT in $ENV_FILE and the
             matching ProxyPass lines in the Apache vhost."
  else
    ok "port $port is free"
  fi
done

step "Apache"
if ! command -v apache2 >/dev/null; then
  warn "apache2 not found"
else
  ok "apache2 present with $(ls /etc/apache2/sites-enabled/ 2>/dev/null | wc -l) enabled site(s)"
  ls /etc/apache2/sites-enabled/ 2>/dev/null | sed 's/^/      - /'
  # Apache serves the FIRST enabled vhost to any request whose Host matches nothing.
  FIRST_SITE=$(ls /etc/apache2/sites-enabled/ 2>/dev/null | head -1)
  echo "      default vhost (first alphabetically): ${FIRST_SITE:-none}"
  if grep -rqs "ServerName\s*$DOMAIN" /etc/apache2/sites-enabled/ ; then
    warn "$DOMAIN is already served by an existing vhost. Remove it first."
  else
    ok "$DOMAIN is not claimed by an existing vhost"
  fi
fi

step "MySQL"
if ! command -v mysql >/dev/null; then
  warn "no mysql client found"
elif ! mysql -e "SELECT 1" >/dev/null 2>&1; then
  if [ -f "$ENV_FILE" ] && grep -q '^DATABASE_URL=mysql://..*@' "$ENV_FILE"; then
    ok "no root socket access, but $ENV_FILE already has a DATABASE_URL, so none is needed"
  else
    warn "cannot connect to MySQL as root via socket. If root has a password,
             create the database and user by hand (see docs/DEPLOY_VPS.md step 3)
             and write $ENV_FILE before re-running."
  fi
else
  ok "MySQL reachable; existing databases left untouched:"
  mysql -N -e "SHOW DATABASES" 2>/dev/null | grep -vE '^(information_schema|performance_schema|mysql|sys)$' | sed 's/^/      - /'
  mysql -e "USE \`$DB_NAME\`" 2>/dev/null && warn "database $DB_NAME already exists; it will be reused as-is"
fi

step "Firewall"
if ufw status 2>/dev/null | grep -q "Status: active"; then
  ok "ufw is active; rules for 80/443 will be added if missing"
  UFW_ACTIVE=1
else
  UFW_ACTIVE=0
  SSH_PORT=$(grep -oP '^\s*Port\s+\K[0-9]+' /etc/ssh/sshd_config 2>/dev/null | head -1)
  warn "ufw is INACTIVE and this script will not enable it.
             Enabling a firewall on a server you are SSH'd into can lock you out,
             and it would also affect your other sites. Ports $WEB_PORT/$API_PORT are
             therefore reachable from the internet unless you close them yourself:
               sudo ufw allow ${SSH_PORT:-22}/tcp && sudo ufw allow 'Apache Full' && sudo ufw enable
             (vinext ignores HOST and binds 0.0.0.0, so $WEB_PORT really is exposed.)"
fi

echo
if [ "$CHECK_ONLY" = "1" ]; then
  echo "Check complete: $PROBLEMS warning(s). Nothing was changed."
  exit 0
fi
[ "$PROBLEMS" = "0" ] || { echo "Resolve the $PROBLEMS warning(s) above, or re-run with --check to review."; read -r -p "Continue anyway? [y/N] " reply; [ "$reply" = "y" ] || exit 1; }

# ---------------------------------------------------------------- apply
[ -d "$APP_DIR/.git" ] || die "$APP_DIR is not a git checkout. Clone the repository there first."

step "Packages"
export DEBIAN_FRONTEND=noninteractive
if [ "$NEED_NODE" = "1" ]; then
  [ "$UPGRADE_NODE" = "1" ] || die "Node 22+ is required but installing it changes Node for every app on this box. Re-run with --upgrade-node, or install Node 22 another way and re-run."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
# Additive only; none of these reconfigure your existing sites.
apt-get install -y git certbot python3-certbot-apache >/dev/null
# The mysql CLI is only needed for backups. On MariaDB boxes the package is
# mariadb-client, and "mysql-client" does not exist - so try the metapackage and
# never let a missing client abort the install.
if ! command -v mysql >/dev/null; then
  apt-get install -y default-mysql-client >/dev/null 2>&1 \
    || apt-get install -y mariadb-client >/dev/null 2>&1 \
    || echo "    note: no mysql client installed; deploy/migrate.sh backups will need one"
fi

step "Service user"
if [ "$SERVICE_USER" = "paisa" ]; then
  id paisa >/dev/null 2>&1 || adduser --system --group --home "$APP_DIR" --no-create-home paisa
  chown -R paisa:paisa "$APP_DIR"
else
  id "$SERVICE_USER" >/dev/null 2>&1 || die "SERVICE_USER=$SERVICE_USER does not exist."
  echo "    using existing user $SERVICE_USER; ownership of $APP_DIR left as-is"
fi
mkdir -p /var/backups/paisa
chown -R "$SERVICE_USER" /var/backups/paisa

step "Database"
# If the env file already carries a filled-in DATABASE_URL, the database was
# provisioned by hand and root socket access is not needed at all.
if [ -f "$ENV_FILE" ] && grep -q '^DATABASE_URL=mysql://..*@' "$ENV_FILE" && ! grep -q 'CHANGE_ME' "$ENV_FILE"; then
  echo "    $ENV_FILE already has a DATABASE_URL; leaving the database alone"
  DB_PASS=""
elif mysql -e "USE \`$DB_NAME\`" 2>/dev/null; then
  echo "    $DB_NAME already exists, leaving it alone"
  DB_PASS=""
else
  DB_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  mysql <<SQL
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  echo "    created $DB_NAME + user $DB_USER (privileges scoped to this database only)"
fi

step "Environment file"
if [ -f "$ENV_FILE" ]; then
  echo "    $ENV_FILE exists, not overwriting"
else
  [ -n "$DB_PASS" ] || die "$ENV_FILE missing but $DB_NAME exists, so its password is unknown. Write $ENV_FILE by hand from deploy/paisa.env.example."
  sed -e "s|^DATABASE_URL=.*|DATABASE_URL=mysql://$DB_USER:$DB_PASS@127.0.0.1:3306/$DB_NAME|" \
      -e "s|paisa.example.com|$DOMAIN|g" \
      "$APP_DIR/deploy/paisa.env.example" > "$ENV_FILE"
  echo "    wrote $ENV_FILE"
fi
chown "$SERVICE_USER" "$ENV_FILE"; chmod 600 "$ENV_FILE"

step "systemd units"
# systemd needs absolute paths, so bake this checkout's location into the units.
for unit in paisa-api paisa-web; do
  sed -e "s|/srv/paisa|$APP_DIR|g" -e "s|^EnvironmentFile=.*|EnvironmentFile=$ENV_FILE|" \
      -e "s|^User=.*|User=$SERVICE_USER|" -e "s|^Group=.*|Group=$SERVICE_USER|" \
      "$APP_DIR/deploy/$unit.service" > "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload
systemctl enable paisa-api paisa-web >/dev/null
echo "    installed (started later, after the first build)"

step "Apache vhost"
# zz- prefix keeps this LAST alphabetically so it can never become the default
# vhost that catches requests meant for your other sites.
sed "s/paisa.example.com/$DOMAIN/g" "$APP_DIR/deploy/paisa-apache.conf" > /etc/apache2/sites-available/zz-paisa.conf
a2enmod proxy proxy_http headers rewrite >/dev/null
a2ensite zz-paisa >/dev/null
apache2ctl configtest
systemctl reload apache2
echo "    zz-paisa.conf enabled; existing sites untouched"

if [ "$UFW_ACTIVE" = "1" ]; then
  step "Firewall"
  ufw allow 'Apache Full' >/dev/null
  ufw deny "$WEB_PORT" >/dev/null; ufw deny "$API_PORT" >/dev/null
  echo "    80/443 allowed, $WEB_PORT/$API_PORT closed to the internet"
fi

cat <<NEXT

============================================================
Done. Your other sites were not modified.

1. Add your Firebase values (database URL and domain are already filled in):

     sudo -e $ENV_FILE

2. Build, migrate, seed and start:

     cd $APP_DIR && sudo -u paisa --preserve-env bash -c 'set -a; . $ENV_FILE; set +a; npm ci --include=dev && npm --prefix apps/web ci --include=dev && npm --workspace @paisa/api run prisma:generate && npm --workspace @paisa/api run prisma:deploy && npm --workspace @paisa/api run seed && npm --prefix apps/web run build' && systemctl restart paisa-api paisa-web

3. Once DNS for $DOMAIN points here:

     sudo certbot --apache -d $DOMAIN

Then every future deploy is one line:

     cd $APP_DIR && ./deploy/deploy.sh
============================================================
NEXT
