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
