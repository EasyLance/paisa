#!/usr/bin/env bash
# Delete every transaction in one book, so you can start capturing again clean.
#
#   ./deploy/reset-ledger.sh book_owner
#   ./deploy/reset-ledger.sh book_owner --with-audit
#
# This is the one operation in here that destroys real ledger data, so it takes
# a verified backup first and makes you type the book id back.
#
# Removed: transactions and everything hanging off them (splits, comments,
# sources), the ingestion events behind them, statement-import records, and the
# period verifications - a month signed off against entries that no longer exist
# is worse than no sign-off at all.
#
# Kept: accounts, categories, rules, recurring plans, budget shares, per-category
# budgets, members and invitations. That is setup, not data.
set -euo pipefail
trap 'status=$?; echo; echo "FAILED at line $LINENO (exit $status): $BASH_COMMAND" >&2; exit $status' ERR

BOOK_ID=""
WITH_AUDIT=no
# A mistyped flag used to be silently ignored, which on a destructive script
# means doing something other than what was asked.
for argument in "$@"; do
  case "$argument" in
    --with-audit) WITH_AUDIT=yes ;;
    -*) echo "Unknown option: $argument" >&2; exit 1 ;;
    *) [ -z "$BOOK_ID" ] || { echo "Give exactly one book id." >&2; exit 1; }; BOOK_ID=$argument ;;
  esac
done

if [ -z "$BOOK_ID" ]; then
  echo "Usage: $0 <bookId> [--with-audit]" >&2
  echo "Find the id on the dashboard URL, or list them with:" >&2
  echo "    SELECT id, name FROM Book;" >&2
  exit 1
fi
# The id lands inside SQL, so pin its shape. Book ids are cuids or seed slugs.
if ! printf '%s' "$BOOK_ID" | grep -qE '^[A-Za-z0-9_-]{1,64}$'; then
  echo "Book id must be letters, digits, underscore or hyphen." >&2
  exit 1
fi

# shellcheck source=deploy/lib-db.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-db.sh"

BOOK_NAME=$(sql "SELECT name FROM Book WHERE id='$BOOK_ID';")
if [ -z "$BOOK_NAME" ]; then
  echo "No book with id '$BOOK_ID' in $DB_NAME. Books available:" >&2
  sql "SELECT id, name FROM Book;" >&2
  exit 1
fi

echo "About to clear the ledger of:  $BOOK_NAME  ($BOOK_ID)"
echo
counts() {
  sql "SELECT 'transactions', COUNT(*) FROM Transaction WHERE bookId='$BOOK_ID'
    UNION ALL SELECT 'ingestion events', COUNT(*) FROM IngestionEvent WHERE bookId='$BOOK_ID'
    UNION ALL SELECT 'statement imports', COUNT(*) FROM Attachment WHERE bookId='$BOOK_ID'
    UNION ALL SELECT 'period reviews', COUNT(*) FROM PeriodReview WHERE bookId='$BOOK_ID'
    UNION ALL SELECT 'audit events', COUNT(*) FROM AuditEvent WHERE bookId='$BOOK_ID';" | sed 's/^/    /'
}
counts
echo
echo "Kept: accounts, categories, rules, recurring plans, budget shares, members."
[ "$WITH_AUDIT" = yes ] && echo "Audit events for this book will ALSO be deleted." || echo "Audit history is kept (pass --with-audit to delete it too)."

# A recurring plan advances nextDueAt as it posts. Deleting those postings does
# not wind it back, so they will not reappear on their own - say so rather than
# letting a month of salary quietly vanish from the ledger.
POSTED=$(sql "SELECT COUNT(*) FROM AuditEvent
  WHERE bookId = '$BOOK_ID' AND action = 'recurring.posted'
    AND entityId IN (SELECT id FROM Transaction WHERE bookId = '$BOOK_ID');")
if [ "${POSTED:-0}" -gt 0 ]; then
  echo
  echo "  !! $POSTED of these were posted by recurring plans. Their plans have already"
  echo "  !! moved nextDueAt forward, so deleting the entries will NOT bring them back."
  echo "  !! Edit the dates afterwards in Accounts & rules if you want them re-posted:"
  sql "SELECT CONCAT('       - ', name, '  next due ', DATE(nextDueAt)) FROM RecurringPlan
    WHERE bookId = '$BOOK_ID' AND active = 1 ORDER BY nextDueAt;"
fi
echo

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/$DB_NAME-before-reset-$(date +%Y%m%d-%H%M%S).sql.gz"
echo "==> Backing up $DB_NAME to $BACKUP_FILE"
dump --single-transaction --routines --triggers "$DB_NAME" | gzip > "$BACKUP_FILE"
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
  DELETE FROM PeriodReview WHERE bookId = '$BOOK_ID';
  DELETE FROM IdempotencyRecord WHERE transactionId NOT IN (SELECT id FROM Transaction);
"
[ "$WITH_AUDIT" = yes ] && sql "DELETE FROM AuditEvent WHERE bookId = '$BOOK_ID';"

echo "==> Remaining in this book"
counts

echo
echo "Done. Restore everything with:"
echo "    gunzip < $BACKUP_FILE | mysql -u $DB_USER -p $DB_NAME"
