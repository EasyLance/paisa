#!/usr/bin/env bash
# Shared database plumbing for the deploy scripts. Source it, don't run it:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib-db.sh"
#
# Provides: APP_DIR, ENV_FILE, BACKUP_DIR, DB_NAME, sql(), dump()
#
# Extracted because three scripts had their own copy of this, and the fix that
# stopped the password reaching the command line had to be made in each of them.
# One copy means the next fix lands everywhere.

APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ENV_FILE=${ENV_FILE:-$APP_DIR/paisa.env}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/paisa}

if [ ! -r "$ENV_FILE" ]; then
  echo "Cannot read $ENV_FILE — create it from deploy/paisa.env.example first." >&2
  exit 1
fi

cd "$APP_DIR"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is not set in $ENV_FILE." >&2
  exit 1
fi

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
# Undo percent-encoding commonly needed in the URL (@ written as %40).
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

# Tab-separated, no column headers — meant to be read by the script.
sql() { mysql --defaults-extra-file="$DB_CREDENTIALS" -N -B "$DB_NAME" -e "$1"; }
# Same, with headers, for output a person reads.
sql_table() { mysql --defaults-extra-file="$DB_CREDENTIALS" --table "$DB_NAME" -e "$1"; }
dump() { mysqldump --defaults-extra-file="$DB_CREDENTIALS" "$@"; }
