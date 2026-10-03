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

Before saying anything is done: `npm run test`, `npm run lint`, for dashboard
changes `npx tsc --noEmit` in `apps/web` plus a build, **and update the docs the
change touches** (see below).

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

## Keeping the docs current

`docs/` is written to stay true, not to be rewritten later from memory. **A
change is not finished until the docs that describe it match.** Update them in
the same turn as the code, not as a follow-up.

| If you changed… | Update |
|---|---|
| A requirement's state, or added/dropped a feature | `docs/prd.md` — the ✅/🟡/⛔ tables |
| Routes, schema, a domain module, deployment, a migration | `docs/architecture.md` |
| A convention, or hit a bug a rule would have prevented | `docs/rules.md` |
| Tokens, a component pattern, layout, or user-facing copy | `docs/design.md` |
| Finished, started or reprioritised work | `docs/tasks.md` **and** `TODO.md` |
| Made a decision, or paid for a new trap | `docs/memory.md` |

Three habits that keep them honest:

- **Bump `Last reviewed`** on any doc you touch.
- **Record the reason, not just the change.** `docs/memory.md` carries a "would
  reverse if" column — a decision without its trigger is folklore.
- **A trap that cost debugging time goes in `docs/memory.md` §3 immediately.**
  That table is the highest-value thing in the folder and only grows if written
  down while it still stings.

`TODO.md` stays the working checklist and wins any disagreement with
`docs/tasks.md`; `CLAUDE.md` stays the operational source and wins over
`docs/memory.md`. The `docs/` versions are the readable overview.

## House rules

- **Money is integer paise** as a string over the wire, `BigInt` in the stores.
  Never floats. Expenses are negative, income and refunds positive; kind and
  amount must change together so the sign can't contradict the type.
- **Statement imports share one pipeline.** `parseStatementRows()` in
  `domain/statement.js` does column detection, narration parsing and row
  fingerprinting; CSV and .xlsx are just two readers in front of it. The
  bank's own running-balance column is used as a checksum on the amounts —
  0 warnings on a real file means every amount was read correctly.
  `domain/xlsx.js` is a dependency-free ZIP+XML reader (SheetJS's npm build is
  stale and advisory-ridden; ExcelJS is a large tree for one shape).
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
- **A book's month is its pay cycle, not the calendar.** `Book.periodStartDay`
  (1–31, default 1) moves the boundary to just before payday, so a month-end
  salary lands at the start of the period it funds instead of the end of the one
  before. `domain/period.js` is the only place that knows the rule; the
  dashboard mirrors the *label* calculation and takes the window itself from the
  summary response so the two cannot disagree on screen.
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

## Tenancy

A workspace is a household and they are fully isolated: every book route
resolves a `BookMembership` and 404s without one, and `listBooks` /
`listWorkspaces` are membership-filtered.

- **Sharing inside a household** — invite from People & access. The invitee
  joins an existing book in the inviter's workspace.
- **A separate household** — `TENANT_SELF_PROVISION=true` makes an unknown
  Firebase identity get its own workspace, two books and its own copy of
  `DEFAULT_CATEGORIES` on first sign-in. An outstanding invitation takes
  precedence, so an invited person still joins the book they were invited to.
  Off by default; **disabling public sign-up in Firebase is the only real
  control** — console-created accounts are never email-verified, so this path
  cannot require verification. When it declines, the API logs
  `Not provisioning a household` with the reason.

Categories are **workspace-scoped**, so any new workspace needs its own copies —
`src/domain/default-categories.js` is the one list, used by the seed, the memory
store and provisioning.

## Master admin

A second console at `/admin`, backed by `/v1/admin/*`, for managing accounts
across every household. Two environment variables — in
`/var/www/projects/Financial-App/paisa.env` on the live droplet, **not**
`/etc/paisa/paisa.env` as `deploy/` assumes (see *Live host drift* below):

```bash
PLATFORM_ADMINS=arjunm295707@gmail.com          # comma-separated, empty by default
FIREBASE_SERVICE_ACCOUNT_FILE=/etc/paisa/firebase-admin.json   # optional
```

- **Matching is on the signed token email** (`request.identityEmail`), not
  `UserProfile.email`. That row is a copy written at sign-up and it drifts — the
  live owner was seeded as `arjunm295707` with no domain, which locked them out
  of their own admin page while the variable was perfectly correct.
- **`PLATFORM_ADMINS` is the whole gate.** Not listed → every `/v1/admin` route
  404s. It is an env var and not a column on purpose: granting it needs shell
  access and a restart, so nothing that can write the database can grant itself
  the ability to read and delete every household.
- A master admin **does not need a household**. With no `UserProfile` they
  authenticate with a profile-less actor; book routes still resolve a membership
  and 404, so it grants no ledger access.
- **Without a service-account key**, the page lists only accounts that have
  signed in, and backup / clear / delete still work. Listing Firebase accounts,
  adding, renaming, disabling and password resets need the key. The page says
  which half is missing rather than failing whole.
- The key file lives at `/etc/paisa/firebase-admin.json`, mode `600`, owned by
  **the service user** — `elance` on the live droplet, not `paisa`. Never in the
  repo: the app directory is readable by the other two apps on that box, and
  `.gitignore` only started covering `*-adminsdk-*.json` on 2026-10-02. Give the
  service account the *Firebase Authentication Admin* role, nothing wider.
- Work the owner out rather than assuming it:
  `SVC=$(systemctl show paisa-api -p User --value); SVC=${SVC:-root}`.
- **No password is ever handled.** A new account is created without one and sent
  a link to set their own; a reset is an email Firebase sends, never a link
  returned to the page.
- Scope: an **export** covers every book the user is a member of, a **wipe**
  only books they own, a **delete** only books nobody else is a member of.
- **Reset to new** is the third level: ledger *and* configuration (accounts,
  rules, budgets, the % plan, recurring plans, invitations, audit trail), then
  `DEFAULT_CATEGORIES` is re-seeded so the books still work. The login, books
  and memberships survive. Categories are workspace-scoped, so it keeps any
  still referenced by a book the reset does not own — `TransactionSplit.category`
  is `Restrict` and would abort the transaction.
- Admin actions go to the **journal** (`journalctl -u paisa-api`), because
  `AuditEvent.workspaceId` is required and the workspace is sometimes the thing
  being deleted.
- **Access requests** are the waiting list. `POST /v1/access-requests` is the
  **only unauthenticated write on the API** — the landing page's "Request
  access" popup — rate-limited to 5 per 10 minutes per IP. The unique email is
  the duplicate guard, and the reply says which of three states the sender is
  in: `received`, `pending`, `granted`. Approving and adding a user outright
  both go through one `grantAccess()`, so somebody the admin created without a
  request is still told "access granted" rather than "wait your turn".

## Live host drift

`deploy/*.service` and `deploy/bootstrap.sh` describe a host that does not
exist. The droplet was set up by hand, and differs:

| `deploy/` assumes | The droplet actually has |
|---|---|
| service user `paisa` | **`elance`** (uid 1000) |
| `EnvironmentFile=/etc/paisa/paisa.env` | **`/var/www/projects/Financial-App/paisa.env`** |
| `/etc/paisa/` created by bootstrap | Did not exist until 2026-10-02 |

So **`bootstrap.sh` would not reproduce this server**, and any instruction that
hardcodes `paisa` or `/etc/paisa/paisa.env` fails on it. Read the running unit
instead of trusting the repo:

```bash
systemctl show paisa-api -p User -p EnvironmentFiles --value
```

## Security

- `AUTH_MODE` **defaults to `firebase`**. Dev mode trusts an `x-dev-user-id`
  header with no token, so it must be asked for explicitly — `npm run serve`
  sets it. Never let that default drift back.
- Security headers live in `deploy/paisa-apache.conf`, not in the app: helmet
  only covers API responses, and the dashboard is served by vinext, which sets
  none. Apache fronts both.
- Anything user- or bank-supplied that reaches a CSV export goes through
  `csvSafe()` — a merchant named `=HYPERLINK(...)` is a formula in Excel, and
  whoever pays you picks their own UPI display name.
- Scripts never put a password on the command line; `ps` is readable by every
  other user on that shared box. Use a 0600 `--defaults-extra-file`.

## Where things stand

Phases 1 and 2 (dashboard, ledger, statement import, budgets) are live. The
Android app is written but not shipped — see `TODO.md`.
