#!/usr/bin/env bash
# Apply pending Prisma migrations, after taking a backup.
#
#   ./deploy/migrate.sh
#
# Deliberately separate from deploy.sh: application code can be rolled back by
# checking out the previous commit, but a migration that drops or rewrites a
# column cannot. This holds real ledger data, so the backup is not optional.
set -euo pipefail

APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# Config lives beside the code: <checkout>/paisa.env (gitignored).
ENV_FILE=${ENV_FILE:-$APP_DIR/paisa.env}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/paisa}

cd "$APP_DIR"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Pull credentials out of DATABASE_URL (mysql://user:pass@host:port/dbname).
proto_stripped=${DATABASE_URL#mysql://}
credentials=${proto_stripped%%@*}
location=${proto_stripped#*@}
DB_USER=${credentials%%:*}
DB_PASS=${credentials#*:}
DB_HOST=${location%%:*}
host_port=${location#*:}
DB_PORT=${host_port%%/*}
DB_NAME=${location##*/}
DB_NAME=${DB_NAME%%\?*}
# Undo percent-encoding commonly needed in the URL.
DB_PASS=$(printf '%b' "${DB_PASS//%/\\x}")

# The password must not reach the command line: `ps` shows every argument to
# every other user on this machine, and this box is shared with other sites.
# A 0600 defaults-file is the only way mysql/mysqldump take one privately.
DB_CREDENTIALS=$(mktemp)
chmod 600 "$DB_CREDENTIALS"
trap 'rm -f "$DB_CREDENTIALS"' EXIT
cat > "$DB_CREDENTIALS" <<CNF
[client]
user=$DB_USER
password=$DB_PASS
host=$DB_HOST
port=$DB_PORT
CNF

mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/$DB_NAME-$STAMP.sql.gz"

echo "==> Pending migrations"
npx --workspace @paisa/api prisma migrate status || true

echo "==> Backing up $DB_NAME to $BACKUP_FILE"
mysqldump --defaults-extra-file="$DB_CREDENTIALS" --single-transaction --routines --triggers \
  "$DB_NAME" | gzip > "$BACKUP_FILE"
echo "    $(du -h "$BACKUP_FILE" | cut -f1) written"

# A backup you have never restored is a guess, not a backup. Verify it is a
# readable dump before changing anything.
if ! gzip -t "$BACKUP_FILE"; then
  echo "Backup is corrupt — refusing to migrate." >&2
  exit 1
fi

read -r -p "==> Apply migrations to $DB_NAME? [y/N] " reply
[ "$reply" = "y" ] || exit 1

npm --workspace @paisa/api run prisma:deploy

echo "==> Restarting API"
sudo systemctl restart paisa-api
sleep 2
curl -fsS http://127.0.0.1:4000/ready && echo

echo "==> Done. Restore with:"
echo "    gunzip < $BACKUP_FILE | mysql -u $DB_USER -p $DB_NAME"
