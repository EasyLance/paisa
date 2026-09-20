#!/usr/bin/env bash
# Remove categorization rules from ONE book, choosing which ones.
#
#   ./deploy/reset-rules.sh                      list the books and their rule counts
#   ./deploy/reset-rules.sh book_owner           pick from a numbered list
#   ./deploy/reset-rules.sh book_owner --all     every rule in that book
#   ./deploy/reset-rules.sh book_owner --match swiggy   only rules mentioning swiggy
#
# Rules are book-scoped, so clearing one household's rules cannot touch another's.
# The book id is validated and every statement is filtered by it.
#
# This is far less destructive than reset-ledger.sh: a rule only affects payments
# captured *after* it was written, so deleting one changes nothing already in the
# ledger. It still writes a restore file first, because 24 rules learned over
# months are not worth retyping.
set -euo pipefail
trap 'status=$?; echo; echo "FAILED at line $LINENO (exit $status): $BASH_COMMAND" >&2; exit $status' ERR

BOOK_ID=""
MODE=pick
MATCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE=all ;;
    --match) shift; MATCH=${1:-}; [ -n "$MATCH" ] || { echo "--match needs a value." >&2; exit 1; } ;;
    --match=*) MATCH=${1#--match=} ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) [ -z "$BOOK_ID" ] || { echo "Give exactly one book id." >&2; exit 1; }; BOOK_ID=$1 ;;
  esac
  shift
done

# shellcheck source=deploy/lib-db.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-db.sh"

# Both of these land inside SQL. Pin their shape rather than trusting them.
if [ -n "$BOOK_ID" ] && ! printf '%s' "$BOOK_ID" | grep -qE '^[A-Za-z0-9_-]{1,64}$'; then
  echo "Book id must be letters, digits, underscore or hyphen." >&2
  exit 1
fi
if [ -n "$MATCH" ] && ! printf '%s' "$MATCH" | grep -qE '^[A-Za-z0-9 ._@-]{1,64}$'; then
  echo "--match may contain letters, digits, spaces and . _ @ - only." >&2
  exit 1
fi

if [ -z "$BOOK_ID" ]; then
  echo "Which book? Each household's rules are separate:"
  echo
  sql_table "SELECT b.id AS book, b.name, w.name AS household,
      (SELECT COUNT(*) FROM CategorizationRule r WHERE r.bookId = b.id) AS rules
    FROM Book b JOIN Workspace w ON w.id = b.workspaceId
    ORDER BY w.name, b.name;"
  echo
  echo "Then: $0 <book> [--all] [--match TEXT]"
  exit 0
fi

BOOK_NAME=$(sql "SELECT name FROM Book WHERE id='$BOOK_ID';")
[ -n "$BOOK_NAME" ] || { echo "No book with id '$BOOK_ID'. Run $0 with no arguments to list them." >&2; exit 1; }

FILTER="r.bookId = '$BOOK_ID'"
[ -z "$MATCH" ] || FILTER="$FILTER AND r.matchValue LIKE '%$MATCH%'"

# A rule that has already filed a lot of payments is load-bearing; one that has
# filed none may have been a mistake. The count comes from the audit trail,
# which is the only place a rule is tied to what it did.
LISTING=$(sql "SELECT r.id, r.priority, r.matchType, r.matchValue, COALESCE(c.name, '?'),
    (SELECT COUNT(*) FROM AuditEvent a
      WHERE a.bookId = r.bookId AND a.action = 'transaction.auto_categorized'
        AND JSON_UNQUOTE(JSON_EXTRACT(a.after, '\$.ruleId')) = r.id)
  FROM CategorizationRule r LEFT JOIN Category c ON c.id = r.categoryId
  WHERE $FILTER ORDER BY r.priority, r.matchValue;")

if [ -z "$LISTING" ]; then
  echo "No rules in '$BOOK_NAME'${MATCH:+ matching \"$MATCH\"}. Nothing to do."
  exit 0
fi

RULES=()
while IFS= read -r line; do RULES+=("$line"); done <<< "$LISTING"
echo "Rules in:  $BOOK_NAME  ($BOOK_ID)${MATCH:+   filtered by \"$MATCH\"}"
echo
printf '  %-4s %-4s %-18s %-34s %-22s %s\n' '#' 'PRI' 'MATCH TYPE' 'VALUE' 'FILES UNDER' 'USED'
index=0
for line in "${RULES[@]}"; do
  index=$((index + 1))
  IFS=$'\t' read -r _id priority matchType matchValue category used <<< "$line"
  printf '  %-4s %-4s %-18s %-34s %-22s %s\n' "$index" "$priority" "$matchType" "${matchValue:0:34}" "${category:0:22}" "$used"
done
echo

if [ "$MODE" = all ]; then
  SELECTION=all
else
  echo "Which to delete?  numbers (1 3 5) · ranges (2-7) · all · blank to cancel"
  read -r -p "> " SELECTION
  [ -n "$SELECTION" ] || { echo "Cancelled. Nothing was deleted."; exit 0; }
fi

CHOSEN=()
if [ "$SELECTION" = all ]; then
  CHOSEN=($(seq 1 ${#RULES[@]}))
else
  for token in $SELECTION; do
    case "$token" in
      [0-9]*-[0-9]*) from=${token%-*}; to=${token#*-}
        [ "$from" -le "$to" ] || { echo "Range $token runs backwards." >&2; exit 1; }
        for n in $(seq "$from" "$to"); do CHOSEN+=("$n"); done ;;
      [0-9]*) CHOSEN+=("$token") ;;
      *) echo "Not a number, range or 'all': $token" >&2; exit 1 ;;
    esac
  done
fi

# A selection of only whitespace parses to nothing; do not fall through to an
# empty IN () list.
[ ${#CHOSEN[@]} -gt 0 ] || { echo "Nothing selected. Nothing was deleted."; exit 0; }

IDS=""
COUNT=0
for n in $(printf '%s\n' "${CHOSEN[@]}" | sort -un); do
  if [ "$n" -lt 1 ] || [ "$n" -gt "${#RULES[@]}" ]; then
    echo "There is no rule $n — the list has ${#RULES[@]}." >&2
    exit 1
  fi
  id=$(cut -f1 <<< "${RULES[$((n - 1))]}")
  IDS="$IDS${IDS:+,}'$id'"
  COUNT=$((COUNT + 1))
  cut -f2- <<< "${RULES[$((n - 1))]}" | awk -F'\t' '{printf "    - %s \"%s\" → %s\n", $2, $3, $4}'
done

echo
echo "$COUNT rule$([ "$COUNT" = 1 ] || echo s) will be deleted from '$BOOK_NAME'."
echo "Entries already in the ledger keep the categories they have — a rule only"
echo "ever affected payments captured after it was written."
echo

mkdir -p "$BACKUP_DIR"
RESTORE_FILE="$BACKUP_DIR/$DB_NAME-rules-$BOOK_ID-$(date +%Y%m%d-%H%M%S).sql"
# Just these rows, as INSERTs, so a mistake is one command away from undone.
dump --no-create-info --skip-add-drop-table --complete-insert --skip-extended-insert \
  --where="id IN ($IDS)" "$DB_NAME" CategorizationRule > "$RESTORE_FILE"
grep -q "INSERT INTO" "$RESTORE_FILE" || { echo "Restore file has no rows — refusing to delete." >&2; exit 1; }
chmod 600 "$RESTORE_FILE"
echo "Restore file: $RESTORE_FILE"

read -r -p "Delete them? [y/N] " reply
[ "$reply" = y ] || { echo "Cancelled. Nothing was deleted."; exit 0; }

# bookId is repeated here on purpose: even if an id were somehow wrong, the
# statement still cannot reach another household's rules.
sql "DELETE FROM CategorizationRule WHERE bookId = '$BOOK_ID' AND id IN ($IDS);"

REMAINING=$(sql "SELECT COUNT(*) FROM CategorizationRule WHERE bookId = '$BOOK_ID';")
echo
echo "Done. '$BOOK_NAME' now has $REMAINING rule$([ "$REMAINING" = 1 ] || echo s)."
echo "Put them back with:"
echo "    mysql -u <user> -p $DB_NAME < $RESTORE_FILE"
