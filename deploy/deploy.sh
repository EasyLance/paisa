#!/usr/bin/env bash
# Manual deploy: pull main, rebuild, restart. Run from anywhere in the checkout.
#
#   ./deploy/deploy.sh
#
# This never touches the database schema. When a release needs a migration,
# run ./deploy/migrate.sh separately — it takes a backup first.
set -euo pipefail

# Any failure names itself. Without this, `set -e` exits silently and a failed
# deploy looks like "nothing happened".
trap 'status=$?; echo; echo "FAILED at line $LINENO (exit $status): $BASH_COMMAND" >&2; echo "Nothing was restarted. Fix the above and re-run." >&2; exit $status' ERR

# Resolve the checkout from this script's own location, so it works from anywhere.
APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# Prefer an env file inside the checkout, fall back to the system one.
# .env is gitignored, so secrets there are not committed.
# Config lives beside the code: <checkout>/paisa.env (gitignored).
ENV_FILE=${ENV_FILE:-$APP_DIR/paisa.env}

cd "$APP_DIR"
echo "Paisa deploy"
echo "  app:  $APP_DIR"
echo "  env:  $ENV_FILE"
echo "  node: $(node -v 2>/dev/null || echo 'NOT FOUND')"
echo "  user: $(whoami)"

# systemd units carry an absolute path; a mismatch means we would build here and
# restart something running from somewhere else. `|| true` because grep exits 1
# when the unit is not installed yet, which is not an error.
UNIT_DIR=$(grep -h '^WorkingDirectory=' /etc/systemd/system/paisa-api.service 2>/dev/null | cut -d= -f2 || true)
# The build below reads ENV_FILE, but the running services read whatever
# EnvironmentFile the unit names. Different files means the dashboard is built
# with one config and the API runs with another.
UNIT_ENV=$(grep -h '^EnvironmentFile=' /etc/systemd/system/paisa-api.service 2>/dev/null | cut -d= -f2 || true)
if [ -n "$UNIT_ENV" ] && [ "$UNIT_ENV" != "$ENV_FILE" ]; then
  echo "  WARNING: building with $ENV_FILE but paisa-api.service loads $UNIT_ENV" >&2
fi
if [ -n "$UNIT_DIR" ] && [ "$UNIT_DIR" != "$APP_DIR" ]; then
  echo "Mismatch: paisa-api.service runs from $UNIT_DIR but this checkout is $APP_DIR." >&2
  echo "Either run deploy.sh from $UNIT_DIR, or update the paths in deploy/paisa-*.service and reinstall them." >&2
  exit 1
fi

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
# --include=dev is required: the env file sets NODE_ENV=production, which would
# otherwise make npm skip devDependencies - and vinext, the dashboard's build
# tool, is one of them.
npm ci --include=dev
# apps/web is not part of the npm workspace and carries its own lockfile.
npm --prefix apps/web ci --include=dev

echo "==> Generating Prisma client"
npm --workspace @paisa/api run prisma:generate

echo "==> Building dashboard"
# Clear the cache first: vinext reuses cached chunks, so a changed NEXT_PUBLIC_*
# value can silently fail to reach the bundle even though the build "succeeds".
rm -rf apps/web/dist apps/web/.vinext
npm --prefix apps/web run build
# The dashboard is useless if auth was compiled out, so fail loudly here rather
# than serving an unauthenticated dashboard on a public URL.
if [ "${NEXT_PUBLIC_AUTH_MODE:-}" = "firebase" ] && ! grep -rq "${NEXT_PUBLIC_FIREBASE_PROJECT_ID:-__unset__}" apps/web/dist/client/; then
  echo "Build finished but the Firebase config is not in the bundle." >&2
  echo "Check the NEXT_PUBLIC_FIREBASE_* values in $ENV_FILE." >&2
  exit 1
fi

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
if [ ! -f /etc/systemd/system/paisa-api.service ]; then
  echo "  Services are not installed yet, so there is nothing to restart." >&2
  echo "  The build above succeeded. Install them with:" >&2
  echo "      sudo bash $APP_DIR/deploy/bootstrap.sh --check your-subdomain.example.com" >&2
  exit 1
fi
sudo systemctl restart paisa-api paisa-web

echo "==> Health check"
# systemd reports Type=simple units "active" the moment the process spawns, so
# poll the real endpoints instead - a service that is up but still connecting to
# the database, or hung before it listens, looks identical to a healthy one here.
probe() { curl -fsS -m 5 -o /dev/null "$1" 2>/dev/null; }
api_url=http://127.0.0.1:${API_PORT:-4000}/health
web_url=http://127.0.0.1:${WEB_PORT:-3000}/
for attempt in $(seq 1 20); do
  probe "$api_url" && api=ok || api=unreachable
  probe "$web_url" && web=ok || web=unreachable
  [ "$api$web" = "okok" ] && break
  [ "$attempt" = 20 ] || sleep 2
done

FAILED=0
for unit in paisa-api paisa-web; do
  state=$(systemctl is-active "$unit" 2>/dev/null || true)
  echo "    $unit: $state"
  [ "$state" = active ] || FAILED=1
done
echo "    api  $api_url -> $api"
echo "    web  $web_url -> $web"
[ "$api" = ok ] && [ "$web" = ok ] || FAILED=1

echo
if [ "$FAILED" = "0" ]; then
  echo "==> Deployed: $(git rev-parse --short HEAD) \"$(git log -1 --pretty=%s)\""
  exit 0
fi

echo "==> Deploy finished but something is not healthy." >&2
for unit in paisa-api paisa-web; do
  case "$unit:$api$web" in paisa-api:ok*) continue ;; paisa-web:*ok) continue ;; esac
  echo >&2
  # A unit that is running but not answering never crashed, so there is no error
  # to find - say what that means rather than leaving 40 lines of journal to read.
  if systemctl is-active --quiet "$unit"; then
    echo "  $unit is running but not answering on its port. It is most likely still" >&2
    echo "  starting, or stuck before it listens - for paisa-api that is nearly always" >&2
    echo "  the database connection (wrong DATABASE_URL, or an @ in the password that" >&2
    echo "  needs to be written %40). Last 20 log lines:" >&2
  else
    echo "  $unit is not running. Last 20 log lines:" >&2
  fi
  echo >&2
  sudo journalctl -u "$unit" -n 20 --no-pager 2>&1 | sed 's/^/      /' >&2
done
echo >&2
echo "  Full logs:  sudo journalctl -u paisa-api -n 200 --no-pager" >&2
exit 1
