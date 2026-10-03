#!/usr/bin/env bash
# Self-check for lib-db.sh. No database and no network: it covers the parts
# that have actually broken — URL parsing, percent-decoding, the 0600
# credentials file, and the backup-directory guard.
#
#   ./deploy/lib-db.test.sh
#
# Written after `migrate.sh` shipped with the body of a heredoc left behind by a
# refactor. `bash -n` could not catch that, because `[client]` is a perfectly
# valid command name. Running the thing is the only check that works.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: expected '$3', got '$2'"; failures=$((failures + 1)); fi; }

printf 'DATABASE_URL=mysql://paisa:p%%40ss@localhost:3306/paisa\n' > "$WORK/paisa.env"
cat > "$WORK/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
. "$LIB"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$DB_USER" "$DB_PASS" "$DB_HOST" "$DB_PORT" "$DB_NAME" "$(stat -f '%Lp' "$DB_CREDENTIALS" 2>/dev/null || stat -c '%a' "$DB_CREDENTIALS")"
PROBE
chmod +x "$WORK/probe.sh"
export LIB="$HERE/lib-db.sh" APP_DIR="$WORK" ENV_FILE="$WORK/paisa.env" BACKUP_DIR="$WORK/backups"

echo "lib-db.sh"
IFS=$'\t' read -r user pass host port name mode < <("$WORK/probe.sh")
check "user from DATABASE_URL"        "$user" "paisa"
# The password routinely contains @, which has to be written %40 in the URL.
check "password percent-decoded"      "$pass" 'p@ss'
check "host"                          "$host" "localhost"
check "port"                          "$port" "3306"
check "database name"                 "$name" "paisa"
# ps is readable by every other user on that shared box.
check "credentials file is private"   "$mode" "600"

# Every script that takes a backup refuses to start without somewhere to put it.
cat > "$WORK/backup.sh" <<'BACKUP'
#!/usr/bin/env bash
set -euo pipefail
. "$LIB"
ensure_backup_dir
echo made
BACKUP
chmod +x "$WORK/backup.sh"
check "creates a writable backup dir" "$(BACKUP_DIR=$WORK/fresh "$WORK/backup.sh")" "made"
mkdir -p "$WORK/locked" && chmod 500 "$WORK/locked"
set +e
BACKUP_DIR="$WORK/locked/paisa" "$WORK/backup.sh" >/dev/null 2>"$WORK/err"
code=$?
set -e
check "refuses an unwritable one"     "$code" "1"
grep -q "sudo install -d" "$WORK/err" \
  && echo "  ok    names the fix" \
  || { echo "  FAIL  the error does not name the fix"; failures=$((failures + 1)); }

# ---- lib-migrate.sh ------------------------------------------------
# The guard that should have caught the missing AccessRequest table. Prisma
# exits non-zero for "pending" AND for "cannot reach the database", so the
# classification is on the text, and the text is real Prisma output.
# The samples are assigned first: a heredoc nested inside $( ) trips the parser
# on an apostrophe.
echo
echo "lib-migrate.sh"
. "$HERE/lib-migrate.sh"

pending_out=$(cat <<'OUT'
Prisma schema loaded from prisma/schema.prisma
Datasource "db": MySQL database "paisa" at "127.0.0.1:3306"

7 migrations found in prisma/migrations

Following migrations have not yet been applied:
20261003000200_access_requests

To apply migrations in development run prisma migrate dev.
OUT
)
current_out=$(cat <<'OUT'
Prisma schema loaded from prisma/schema.prisma
Datasource "db": MySQL database "paisa" at "127.0.0.1:3306"

7 migrations found in prisma/migrations

Database schema is up to date!
OUT
)
unreachable_out=$(cat <<'OUT'
Prisma schema loaded from prisma/schema.prisma
Datasource "db": MySQL database "paisa" at "127.0.0.1:3306"
Error: P1001: Cannot reach database server at 127.0.0.1:3306
OUT
)

check "pending is pending"            "$(migration_verdict "$pending_out")"     "pending"
check "up to date is current"         "$(migration_verdict "$current_out")"     "current"
# The one that mattered: any failure used to read as "nothing pending", and the
# deploy restarted the new code against the old schema.
check "unreachable is unknown"        "$(migration_verdict "$unreachable_out")" "unknown"
check "a missing binary is unknown"   "$(migration_verdict "npm error could not determine executable to run")" "unknown"
check "empty output is unknown"       "$(migration_verdict "")"                 "unknown"

# And deploy.sh must actually use it rather than an inline grep that fails open.
if grep -q 'migration_verdict' "$HERE/deploy.sh"; then
  echo "  ok    deploy.sh classifies rather than greps"
else
  echo "  FAIL  deploy.sh is not using migration_verdict"; failures=$((failures + 1))
fi
# Code only, not comments, and not this file — both mention it on purpose.
if grep -lE '^[^#]*npx[[:space:]]+--workspace' "$HERE"/*.sh | grep -qv 'lib-db.test.sh'; then
  echo "  FAIL  npx --workspace is back; npx ignores the flag and runs in the wrong directory"; failures=$((failures + 1))
else
  echo "  ok    no script invokes prisma through npx --workspace"
fi

echo
# A heredoc body orphaned by a refactor parses fine and dies at runtime.
for script in "$HERE"/*.sh; do
  bash -n "$script" || { echo "  FAIL  $script does not parse"; failures=$((failures + 1)); }
done
if grep -lE '^(\[client\]|CNF)$' "$HERE"/*.sh | grep -qv 'lib-db.sh'; then
  echo "  FAIL  a credentials heredoc has escaped lib-db.sh"; failures=$((failures + 1))
else
  echo "  ok    only lib-db.sh writes the credentials file"
fi

[ "$failures" -eq 0 ] && echo "all deploy checks passed" || { echo "$failures failed" >&2; exit 1; }
