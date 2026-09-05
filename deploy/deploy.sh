#!/usr/bin/env bash
# Manual deploy: pull main, rebuild, restart. Run from /srv/paisa on the VPS.
#
#   ./deploy/deploy.sh
#
# This never touches the database schema. When a release needs a migration,
# run ./deploy/migrate.sh separately — it takes a backup first.
set -euo pipefail

APP_DIR=${APP_DIR:-/srv/paisa}
ENV_FILE=${ENV_FILE:-/etc/paisa/paisa.env}

cd "$APP_DIR"

if [ ! -r "$ENV_FILE" ]; then
  echo "Cannot read $ENV_FILE — create it from deploy/paisa.env.example first." >&2
  exit 1
fi

echo "==> Pulling main"
git pull --ff-only

# The dashboard inlines every NEXT_PUBLIC_* value at build time, so these must be
# in the environment before the build below, not just at runtime.
echo "==> Loading $ENV_FILE"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "==> Installing dependencies"
npm ci
# apps/web is not part of the npm workspace and carries its own lockfile.
npm --prefix apps/web ci

echo "==> Generating Prisma client"
npm --workspace @paisa/api run prisma:generate

echo "==> Building dashboard"
npm --prefix apps/web run build

echo "==> Checking for pending migrations"
if npx --workspace @paisa/api prisma migrate status 2>&1 | grep -qi "not yet been applied"; then
  echo
  echo "  !! This release contains migrations that have NOT been applied."
  echo "  !! The new code is about to run against the old schema."
  echo "  !! Stop now and run ./deploy/migrate.sh, then re-run this script."
  echo
  read -r -p "  Continue anyway? [y/N] " reply
  [ "$reply" = "y" ] || exit 1
fi

echo "==> Restarting services"
sudo systemctl restart paisa-api paisa-web

sleep 3
echo "==> Health check"
curl -fsS http://127.0.0.1:4000/health && echo
curl -fsS -o /dev/null -w "dashboard: %{http_code}\n" http://127.0.0.1:3000/

echo "==> Deployed"
