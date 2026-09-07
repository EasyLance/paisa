#!/usr/bin/env bash
# Build and serve the dashboard the way production does: real build, Firebase auth,
# NEXT_PUBLIC_* values compiled in. Used by .claude/launch.json so "run the webapp"
# never serves a dev-auth build by accident.
set -euo pipefail
cd "$(dirname "$0")/.."

# vinext needs Node 22+; the shell default here is 20.
for candidate in "$HOME"/.nvm/versions/node/v2[2-9]*/bin "$HOME"/.nvm/versions/node/v[3-9]*/bin; do
  [ -d "$candidate" ] && PATH="$candidate:$PATH" && break
done
command -v node >/dev/null && [ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -ge 22 ] || {
  echo "Need Node 22+; found $(node -v 2>/dev/null || echo none)." >&2; exit 1; }

ENV_FILE=${ENV_FILE:-.env.firebase-local}
if [ -f "$ENV_FILE" ]; then
  set -a; . "./$ENV_FILE"; set +a
  echo "Loaded $ENV_FILE (auth: ${NEXT_PUBLIC_AUTH_MODE:-unset})"
else
  echo "No $ENV_FILE — building without Firebase config, so sign-in will be skipped." >&2
fi

npm --prefix apps/web run build
# The env file's PORT belongs to the API; the dashboard needs its own.
exec env PORT=3000 npm --prefix apps/web run start
