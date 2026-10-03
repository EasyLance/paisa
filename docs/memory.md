# 🧠 Project Context

**Paisa — Household Finance Platform**

The things you cannot read off the code: decisions and their reasons, the traps
already paid for, and what would make us change our minds.

> **Last reviewed** 2026-10-03 · Working rules live in `/CLAUDE.md`

---

## 1. Facts

| | |
|---|---|
| **Live** | <https://paisa.easylancefreelance.com> |
| **Host** | DigitalOcean droplet, **shared** with a Laravel app and a React site |
| **Path** | `/var/www/projects/Financial-App` |
| **Database** | MariaDB (*not* MySQL), schema `paisa` |
| **Auth** | Firebase project `paisa-easylance` — web app registered, **Android not** |
| **Owner** | `arjunm295707@gmail.com` → books `book_owner`, `book_home` |
| **Second household** | `tptp.jadheer@gmail.com` → own workspace, provisioned on first sign-in |
| **Deploy** | Manual, `./deploy/deploy.sh`, from `main`. No CI |
| **Service user** | `elance` (uid 1000) — *not* `paisa` as `deploy/` assumes |
| **Env file** | `/var/www/projects/Financial-App/paisa.env` — *not* `/etc/paisa/paisa.env` |
| **Master admin** | `arjunm295707@gmail.com`, via `PLATFORM_ADMINS` + a key at `/etc/paisa/firebase-admin.json` (`600 elance:elance`). Verified against the live project 2026-10-02 |
| **Node** | 22+ required; the shell defaults to 20.16 |
| **Figma** | [Paisa Landing Page — Editable UI](https://www.figma.com/design/6Nht9mkYayMYdp33qbfKSb) in Arjun's **Private** workspace |

### 1.1 Landing-page design source

- Figma file key: `6Nht9mkYayMYdp33qbfKSb`.
- `01 Components & Tokens` contains the local design system; `02 Landing Screens`
  contains the desktop and mobile landing pages.
- The design uses editable Figma layers rather than flattened screenshots.
- Reusable assets include the Paisa logo, primary/outline/text button variants,
  trust points, transaction rows and category rows.
- The file includes colour and spacing variables, nine Geist text styles and two
  shared shadow effects.
- Source previews are stored in `design/landing-page/paisa-landing-desktop.png`
  and `design/landing-page/paisa-landing-mobile.png`.

---

## 2. Decisions and Why

| Decision | Reason | Would reverse if |
|---|---|---|
| **No BullMQ, no Redis** | One household. A `setInterval` in the API does the scheduling for free | Jobs outlive a request, or a second API process appears |
| **Two stores, one interface** | Tests run with no database | They diverge again without the domain layer holding |
| **Row immutability dropped** | The audit trail is the real safeguard. A typo in a manual entry was permanent | — |
| **Imported figure kept forever** | `TransactionSource.importedAmount` means an edit never erases what the bank said | — |
| **XLSX read without a dependency** | SheetJS's npm build is stale with advisories; ExcelJS is a large tree for one shape. 90 lines of ZIP + XML instead | A spreadsheet shape appears that this cannot read |
| **Budgets as % of income** | A rupee budget is stale the month income changes | — |
| **Expected income from recurring plans** | Salary lands on the last working day; % of income-so-far reads zero all month | — |
| **Recurring posts as `pending_review`** | A plan is a prediction. The bank's own credit will arrive too | Reconciliation can match them automatically |
| **Transfers counted in the breakdown** | "Where your money went" must account for money that went to your own savings | — |
| **CSP with `unsafe-inline`** | vinext emits ~16 nonce-less inline scripts. A strict policy white-screens the dashboard | vinext gains nonce support |
| **Provisioning skips email verification** | Console-created accounts are never verified, and verification stops nobody who owns their own address | — |
| **Public pages written honestly** | No invented testimonials, no returns policy for a product that is not sold | It becomes a real product |
| **One `deploy/lib-db.sh`** | Three scripts each had their own `DATABASE_URL` parsing, so the fix that kept the password off the command line had to be made three times | — |
| **Master admin is an env var, not a column** | `PLATFORM_ADMINS`. A column can be set by anything that can write the database — an injection, a restored backup, a mistyped seed. This needs shell access and a restart | Admins ever need to be managed by non-operators |
| **No `firebase-admin` package** | It pulls google-auth-library, gaxios, Firestore and Storage in for six REST calls the API can make with the `jose` it already has. Same reasoning as the XLSX reader | Google changes the Identity Toolkit API, or we need more than user management |
| **The service-account key is optional** | A key that can mint a token for any user should not be required to boot. Without one the admin page shows the ledger half and says what is missing | — |
| **Admin actions are journalled, not audited** | `AuditEvent.workspaceId` is required, and the workspace is sometimes the thing being deleted. The journal is the record that survives | AuditEvent gains a nullable workspace |
| **An export covers what the user can read; a wipe only what they own** | A CA has a membership in a household, not a ledger. Wiping them must not empty somebody else's books | — |
| **A book's month is its pay cycle** | Paid on the last working day, a calendar month puts the salary that funds November into October: a month-long deficit that leaps on the 30th. `Book.periodStartDay` moves the boundary to just before payday | — |
| **A plain day number, not a working-day calendar** | Payday moves between the 28th and the 31st, but all of those sit inside a cycle starting on the 26th. Predicting payday needs a calendar; bucketing it does not | Someone is paid mid-month and the drift crosses the boundary |
| **Start day capped at 28** | No month is missing the 28th, so February never needs a special case | — |
| **A cycle past mid-month is labelled by the month after** | 26 Oct – 25 Nov is "November", because that is the money that buys November | — |
| **Rules survive a ledger reset** | They are learned configuration, not data. Re-importing after a wipe should auto-categorise, not start from nothing |
| **Landing page at `/`, dashboard also at `/`** | `page.tsx` renders the landing page when signed out instead of moving the dashboard to `/app`. Invitation links are `/#people?invite=…` and already in people's inboxes; moving the dashboard would break every one of them | The dashboard needs server rendering or its own metadata |
| **An invitation link still opens the form** | A signed-out visitor at `/` gets marketing, but one carrying an invite token gets the sign-in card — their link is the only way in | — |
| **`localStorage` decides the first paint** | Without it the dark loading card flashed in front of the landing page, or the landing page flashed in front of a returning user. It is a rendering hint and grants nothing | — | — |

---

## 3. Traps Already Paid For

### 3.1 Build & Deploy

| Trap | What happens | Guard |
|---|---|---|
| Node 20 | `does not provide an export named 'glob'` | Use 22+ |
| Building without the Firebase env | A successful build serving an **unauthenticated** dashboard | `deploy.sh` greps the bundle and fails |
| Stale `apps/web/dist` | Old code served, build reports success | `rm -rf dist .vinext` first |
| `npm ci` with `NODE_ENV=production` | Skips devDeps → `vinext: not found` | `--include=dev` |
| Health check right after restart | False failure — the API takes ~3s to bind | Poll, don't curl once |

### 3.2 systemd & Apache

| Trap | Detail |
|---|---|
| `EnvironmentFile=` applies **after** `Environment=` | Regardless of line order. `paisa-web` sets `PORT` inside `ExecStart` |
| `vinext start` ignores `HOST` | Binds `0.0.0.0`. Only Apache keeps it private. The API honours `HOST` |
| Security headers | helmet covers API responses only; the dashboard is served by vinext, which sets none |

### 3.3 Config

| Trap | Detail |
|---|---|
| `??` vs `\|\|` in the seed | An unset env var arrives as `""`, which `??` does not catch → `P2002` on the second insert |
| `@` in `DATABASE_URL` | Must be written `%40` |
| `FIREBASE_PROJECT_ID` | Needed **as well as** `NEXT_PUBLIC_FIREBASE_PROJECT_ID`. Missing it = 401 after a successful sign-in |
| MariaDB | The client package is `mariadb-client`, not `mysql-client` |

### 3.4 Application

| Trap | Detail |
|---|---|
| `DELETE` with `content-type` and no body | 400 at parse time |
| A 204 response | No JSON to read — the delete succeeded while the UI reported failure |
| `money()` dropping the sign | A negative balance rendered as a healthy positive |
| `limit=100` with a discarded cursor | 172 rows imported, 100 shown — it looked like a failed import |
| Dashboard pinned to the current month | Import an older statement → every tile reads zero |
| Idempotency keys under 8 characters | Silent 400s that a loose test blamed on the code |
| `next/link` in vinext | `ee is not a function` at runtime. Use plain `<a>` |
| `sourceReference` is `manual:<id>` for **every** `createTransaction` | Including recurring postings. To find them, look for the `recurring.posted` audit event — not the source reference |
| Deleting a recurring posting does not wind back `nextDueAt` | The plan has already advanced, so the entry never reappears. `reset-ledger.sh` warns and lists the affected plans |
| The dashboard mirrors `currentPeriodLabel` in TypeScript | `apps/web` cannot import from `apps/api`. Only the *label* is duplicated; the window printed under it comes from the summary response, so the header cannot contradict the figures |
| `UserProfile.email` is a **copy**, and it drifts | The live owner row was seeded as `arjunm295707`, no domain — so the master-admin check against it failed while `PLATFORM_ADMINS` was correct. Anything deciding *who someone is* compares the **signed token** email (`request.identityEmail`), never the row |
| A heredoc body orphaned by a refactor | Extracting the credentials file into `lib-db.sh` left `[client] … CNF` behind in `migrate.sh`. `bash -n` passes, because `[client]` is a valid command name — it only dies when run. `deploy/lib-db.test.sh` now greps for it |
| `/var/backups` is root-owned | A service user cannot `mkdir -p /var/backups/paisa`. `ensure_backup_dir` names the `sudo install -d` fix instead of dying on "Permission denied" |
| `npx --workspace` is not a thing | Only `npm` takes `--workspace`. `migrate.sh` was silently swallowing its own migration-status output through `|| true` |
| `accounts:update` does not echo `disabled` back | Shaping its response reported every disable as a no-op, although the disable had worked. `updateFirebaseUser` reads the account back with `accounts:lookup` instead of trusting the write |
| A profile can outlive its Firebase account | Delete the account in the console and the ledger row stays. Email and disabled changes now 409 with `FIREBASE_ACCOUNT_MISSING`; the name is still editable |
| `node --watch` + a port already held | The restart dies with `EADDRINUSE` and the **old** process keeps serving, so edits appear to do nothing and env changes seem ignored. `lsof -ti:4000 \| xargs kill -9` first |
| `Comment.author` and `BookInvitation.invitedBy` are `Restrict` | Deleting a `UserProfile` fails until their comments and sent invitations go first |
| A `Book` delete cascading to `IngestionEvent` | `TransactionSource.ingestionEvent` is `Restrict`, and MariaDB does not order cascades. Delete sources → transactions → events explicitly, the order `reset-ledger.sh` already uses |
| The API's eslint config lists its globals by hand | `fetch`, `URLSearchParams` and `AbortSignal` were all `no-undef` until added |
| A bare `nav{}` selector in `globals.css` | It was the dashboard's mobile bottom bar — `repeat(6,1fr)` — and it reshaped the footer of **every** public page into six columns. Scoped to `.sidebar nav`; public styles now live in `landing.css` |
| An inline `<svg>` with no `width`/`height` | Fills its container. The leaf logo rendered ~300px tall inside the sign-in card |
| `window.scrollTo` while verifying a page | `html{scroll-behavior:smooth}` animates it, so a screenshot taken straight after catches the page mid-flight and looks blank |
| `node_modules/@cloudflare/workerd-darwin-arm64/bin` empty | `vinext build` fails at **config load** with a confusing "installed on another platform" message naming the same platform twice. `npm install @cloudflare/workerd-darwin-arm64 --no-save` |

---

## 4. Bank Formats

| Bank | Format | Narration shape | Verified |
|---|---|---|---|
| 🟦 **SBI** | CSV | `UPI/DR/<ref>/<NAME>/<BANK>/<vpa>/Paid` — slashes, hard-wrapped mid-token | 17 rows, 0 warnings |
| 🟥 **HDFC** | `.xlsx` | `UPI-<NAME>-<vpa>-<IFSC>-<ref>-<note>` — hyphens; also `NEFT CR-`, `ACH D-`, `IB BILLPAY DR-` | 172 rows, 0 warnings |

Two quirks worth remembering:

1. SBI wraps text mid-token with a newline plus one space — `smohanes\n h1` is
   really `smohanesh1`.
2. A hyphen *inside* an HDFC VPA splits the segment, so the payee is the nearest
   segment **with a space** in it.

> **The running-balance column is the checksum.** Zero warnings on a real file
> means every amount was read correctly. It is the strongest signal available,
> and it is free.

---

## 5. Working Style

- **Ponytail mode** — the laziest thing that actually works. Read the whole flow
  first, then pick the highest rung that holds.
- Deployment ends with `cd /var/www/projects/Financial-App && ./deploy/deploy.sh`
  — never a `git push` command.
- **Verify against the live site** when a bug is reported. Twice now the
  diagnosis came from reading the browser's IndexedDB or paging the live API,
  not from guessing at the source.
- **Say what was skipped.** A half-fix reported as complete is worse than no fix.

---

## 6. Open Questions

| Question | Blocked on |
|---|---|
| Is Paisa staying private, or becoming a product? | Changes the public pages, the tenancy model and the Play Store path |
| Should refunds reduce spending or add to income? | A definition, not code |
| Should savings leave "Spent" entirely? | Currently transfers do; expense-typed investments do not |
| Which PDF layout should the parser target? | One real password-protected statement |
