# Working on Paisa

Android-first household finance app for India. Invite-only, used by Arjun's
household plus their CA. Live at <https://paisa.easylancefreelance.com>.

## Layout

```text
apps/web       React dashboard — vinext (Vite), NOT an npm workspace, own lockfile
apps/api       Fastify REST API + Prisma schema
apps/worker    BullMQ stubs — no Redis is running, effectively unused
apps/mobile    Flutter Android app + Kotlin SMS bridge
deploy/        bootstrap, deploy, migrate, reset-ledger, systemd units, Apache config
```

## Commands

```bash
npm run dev      # dashboard (apps/web)
npm run serve    # API
npm run test     # API tests (vitest) — the only test suite
npm run lint     # all three JS packages
```

Before saying anything is done: `npm run test`, `npm run lint`, and for dashboard
changes `npx tsc --noEmit` in `apps/web` plus a build.

**Node 22+ is required.** The shell defaults to 20.16, which fails with
`does not provide an export named 'glob'` — vinext needs `node:fs/promises`
`glob`. Use `export PATH="$HOME/.nvm/versions/node/v26.5.0/bin:$PATH"`.

Building the dashboard **needs the Firebase env sourced**, or you ship a bundle
with auth compiled out:

```bash
cd apps/web && set -a && . ../../.env.firebase-local && set +a && rm -rf dist .vinext && npm run build
```

## Deploying

Arjun deploys manually on a DigitalOcean droplet at
`/var/www/projects/Financial-App`, which also hosts a Laravel app and a React
site. End work with:

```bash
cd /var/www/projects/Financial-App && ./deploy/deploy.sh
```

`deploy.sh` pulls, installs, rebuilds and restarts. **A release with a migration
needs `./deploy/migrate.sh` first** (it backs up before touching the schema);
`deploy.sh` detects pending migrations and stops. Do not offer `git push`
commands — give the deploy command.

`deploy/reset-ledger.sh <bookId>` wipes one book's transactions after a verified
backup. Arjun's book is `book_owner`.

## House rules

- **Money is integer paise** as a string over the wire, `BigInt` in the stores.
  Never floats. Expenses are negative, income and refunds positive; kind and
  amount must change together so the sign can't contradict the type.
- **Two stores implement the same interface**: `memory-store.js` (tests, demo)
  and `prisma-store.js` (MariaDB). Any behaviour they must agree on belongs in
  `src/domain/` — they have silently diverged before. See `categorization.js`,
  `spending.js`, `recurring.js`, `statement-csv.js`.
- **Every mutation writes an audit event** with before/after. That is what
  replaced row immutability: a transaction can now be fully edited, but an
  imported row keeps the bank's figure in `TransactionSource.importedAmount`
  forever.
- **`spendByCategory` must account for everything that left the account** —
  uncategorized payments, split parts, and outgoing transfers. The dashboard
  asserts `sum(byCategory) === spentMinor + movedMinor`; there is a test.
- Non-trivial logic leaves one runnable check behind. Tests live in
  `apps/api/test/api.test.js`.
- Timezone is Asia/Kolkata. Dates from a form anchor to midnight in the book's
  timezone via `dateAt()`, so a month-end salary doesn't slip into next month.

## Gotchas that have already cost time

- `vinext start` ignores `HOST` and binds `0.0.0.0`; the API honours
  `HOST=127.0.0.1`. Apache reverse-proxies both on one origin, so there is no
  CORS to configure.
- systemd applies `EnvironmentFile=` **after** `Environment=` regardless of line
  order — `paisa-web.service` sets `PORT` inside `ExecStart` because of this.
- Vite inlines `NEXT_PUBLIC_*` at **build** time. Everything else is runtime.
  `FIREBASE_PROJECT_ID` and `NEXT_PUBLIC_FIREBASE_PROJECT_ID` are both needed.
- A stale `apps/web/dist` looks like a successful build while serving old code.
  Always `rm -rf dist .vinext` first.
- Seed env vars use `||` not `??`: an empty string must fall back.
- `DATABASE_URL` passwords need `@` written as `%40`.
- MariaDB, not MySQL — the client package is `mariadb-client`.
- The API takes ~3s to bind. Health checks must poll, not curl once.
- `DELETE` with a `content-type` header and no body is a 400 at parse; a 204
  response has no JSON to read.

## Where things stand

Phases 1 and 2 (dashboard, ledger, statement import, budgets) are live. The
Android app is written but not shipped — see `TODO.md`.
