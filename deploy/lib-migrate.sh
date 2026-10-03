#!/usr/bin/env bash
# Classifying `prisma migrate status`. Its own file, not lib-db.sh: deploy.sh
# must not pull in the credentials machinery, and this needs no database.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib-migrate.sh"
#   case "$(migration_verdict "$output")" in pending|current|unknown) ... esac

# Prisma exits non-zero BOTH when migrations are pending and when it cannot
# reach the database, so the exit code cannot tell them apart — only the text
# can. Anything that is neither answer is `unknown`, and the caller must treat
# that as a reason to stop. Reading "could not tell" as "nothing to do" is how
# the AccessRequest table came to be missing on 2026-10-03 while the code that
# queries it was already live and returning 500s.
migration_verdict() {
  if printf '%s\n' "$1" | grep -qi "not yet been applied"; then
    echo pending
  elif printf '%s\n' "$1" | grep -qiE "up to date|No migration found in prisma/migrations"; then
    echo current
  else
    echo unknown
  fi
}
