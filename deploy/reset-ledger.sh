#!/usr/bin/env bash
# Delete every transaction in one book, so you can start capturing again clean.
#
#   ./deploy/reset-ledger.sh book_owner
#   ./deploy/reset-ledger.sh book_owner --with-audit
#
# This is the one operation in here that destroys real ledger data, so it takes
# a verified backup first and makes you type the book id back. It removes
# transactions, their splits/comments/sources, the ingestion events behind them,
# and the statement-import records. It leaves your setup alone: accounts,
# categories, rules, recurring plans, budgets, members and invitations stay.
set -euo pipefail
trap 'status=$?; echo; echo "FAILED at line $LINENO (exit $status): $BASH_COMMAND" >&2; exit $status' ERR

BOOK_ID=${1:-}
WITH_AUDIT=${2:-}
if [ -z "$BOOK_ID" ]; then
  echo "Usage: $0 <bookId> [--with-audit]" >&2
  echo "Find the id on the dashboard URL, or list them with:" >&2
  echo "    SELECT id, name FROM Book;" >&2
  exit 1
fi

APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
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
DB_PASS=$(printf '%b' "${DB_PASS//%/\\x}")

sql() { mysql -N -B -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$1"; }

BOOK_NAME=$(sql "SELECT name FROM Book WHERE id='$BOOK_ID';")
if [ -z "$BOOK_NAME" ]; then
  echo "No book with id '$BOOK_ID' in $DB_NAME. Books available:" >&2
  sql "SELECT id, name FROM Book;" >&2
  exit 1
fi

echo "About to clear the ledger of:  $BOOK_NAME  ($BOOK_ID)"
echo
sql "SELECT 'transactions', COUNT(*) FROM Transaction WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'ingestion events', COUNT(*) FROM IngestionEvent WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'statement imports', COUNT(*) FROM Attachment WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'audit events', COUNT(*) FROM AuditEvent WHERE bookId='$BOOK_ID';" | sed 's/^/    /'
echo
echo "Kept: accounts, categories, rules, recurring plans, budgets, members."
[ "$WITH_AUDIT" = "--with-audit" ] && echo "Audit events for this book will ALSO be deleted." || echo "Audit history is kept (pass --with-audit to delete it too)."
echo

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/$DB_NAME-before-reset-$(date +%Y%m%d-%H%M%S).sql.gz"
echo "==> Backing up $DB_NAME to $BACKUP_FILE"
mysqldump --single-transaction --routines --triggers \
  -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" | gzip > "$BACKUP_FILE"
echo "    $(du -h "$BACKUP_FILE" | cut -f1) written"
# A backup you cannot read is not a backup.
gzip -t "$BACKUP_FILE" || { echo "Backup is corrupt - refusing to delete anything." >&2; exit 1; }

echo
read -r -p "Type the book id to confirm deletion: " reply
[ "$reply" = "$BOOK_ID" ] || { echo "Did not match. Nothing was deleted."; exit 1; }

# Order matters: TransactionSource pins its IngestionEvent with ON DELETE
# RESTRICT, so the sources have to go before the events they point at. Deleting
# a Transaction cascades to its splits, comments and sources, but do the sources
# explicitly so the restriction is lifted whatever the cascade order turns out
# to be. Attachment.transactionId is SET NULL, so import rows survive and are
# removed on their own line.
echo "==> Deleting"
sql "
  DELETE ts FROM TransactionSource ts JOIN Transaction t ON t.id = ts.transactionId WHERE t.bookId = '$BOOK_ID';
  DELETE FROM Transaction WHERE bookId = '$BOOK_ID';
  DELETE FROM IngestionEvent WHERE bookId = '$BOOK_ID';
  DELETE FROM Attachment WHERE bookId = '$BOOK_ID';
  DELETE FROM IdempotencyRecord WHERE transactionId NOT IN (SELECT id FROM Transaction);
"
[ "$WITH_AUDIT" = "--with-audit" ] && sql "DELETE FROM AuditEvent WHERE bookId = '$BOOK_ID';"

echo "==> Remaining in this book"
sql "SELECT 'transactions', COUNT(*) FROM Transaction WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'ingestion events', COUNT(*) FROM IngestionEvent WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'statement imports', COUNT(*) FROM Attachment WHERE bookId='$BOOK_ID'
  UNION ALL SELECT 'audit events', COUNT(*) FROM AuditEvent WHERE bookId='$BOOK_ID';" | sed 's/^/    /'

echo
echo "Done. Restore everything with:"
echo "    gunzip < $BACKUP_FILE | mysql -u $DB_USER -p $DB_NAME"
