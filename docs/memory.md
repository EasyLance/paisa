# Paisa — Project Context

> The things you cannot read off the code. Decisions, their reasons, and the
> traps already paid for.
> **Last reviewed** 2026-09-20 · Working rules live in `/CLAUDE.md`

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
| **Node** | 22+ required; the shell defaults to 20.16 |

## 2. Decisions and why

| Decision | Reason | Would reverse if |
|---|---|---|
| **No BullMQ, no Redis** | One household. A `setInterval` in the API does the scheduling for free | Jobs outlive a request, or a second API process appears |
| **Two stores, one interface** | Tests run with no database | They diverge again without the domain layer holding |
| **Row immutability dropped** | The audit trail is the real safeguard. A typo in a manual entry was permanent | — |
| **Imported figure kept forever** | `TransactionSource.importedAmount` means an edit never erases what the bank said | — |
| **XLSX read without a dependency** | SheetJS's npm build is stale with advisories; ExcelJS is a large tree for one shape. 90 lines of ZIP + XML instead | A second spreadsheet shape appears that this cannot read |
| **Budgets as % of income** | A rupee budget is stale the month income changes | — |
| **Expected income from recurring plans** | Salary lands on the last working day; % of income-so-far reads zero all month | — |
| **Recurring posts as `pending_review`** | A plan is a prediction. The bank's own credit will arrive too | Reconciliation can match them automatically |
| **Transfers counted in the breakdown** | "Where your money went" must account for money that went to your own savings | — |
| **CSP with `unsafe-inline`** | vinext emits ~16 nonce-less inline scripts. A strict policy white-screens the dashboard | vinext gains nonce support |
| **Provisioning skips email verification** | Console-created accounts are never verified, and verification stops nobody who owns their own address | — |
| **Public pages written honestly** | No invented testimonials, no returns policy for a product that is not sold | It becomes a real product |

## 3. Traps already paid for

### Build & deploy

| Trap | What happens | Guard |
|---|---|---|
| Node 20 | `does not provide an export named 'glob'` | Use 22+ |
| Building without the Firebase env | A successful build serving an **unauthenticated** dashboard | `deploy.sh` greps the bundle and fails |
| Stale `apps/web/dist` | Old code served, build reports success | `rm -rf dist .vinext` first |
| `npm ci` with `NODE_ENV=production` | Skips devDeps → `vinext: not found` | `--include=dev` |
| Health check right after restart | False failure — the API takes ~3s to bind | Poll, don't curl once |

### systemd & Apache

| Trap | Detail |
|---|---|
| `EnvironmentFile=` applies **after** `Environment=` | Regardless of line order. `paisa-web` sets `PORT` inside `ExecStart` |
| `vinext start` ignores `HOST` | Binds `0.0.0.0`. Only Apache keeps it private. The API honours `HOST` |
| Security headers | helmet covers API responses only; the dashboard is served by vinext, which sets none |

### Config

| Trap | Detail |
|---|---|
| `??` vs `\|\|` in the seed | An unset env var arrives as `""`, which `??` does not catch → `P2002` on the second insert |
| `@` in `DATABASE_URL` | Must be `%40` |
| `FIREBASE_PROJECT_ID` | Needed **as well as** `NEXT_PUBLIC_FIREBASE_PROJECT_ID`. Missing it = 401 after a successful sign-in |
| MariaDB | The client package is `mariadb-client`, not `mysql-client` |

### Application

| Trap | Detail |
|---|---|
| `DELETE` with `content-type` and no body | 400 at parse time |
| A 204 response | No JSON to read — the delete succeeded while the UI reported failure |
| `money()` dropping the sign | A negative balance rendered as a healthy positive |
| `limit=100` with a discarded cursor | 172 rows imported, 100 shown, and it looked like a failed import |
| Dashboard pinned to the current month | Import an older statement → every tile reads zero |
| Idempotency keys under 8 characters | Silent 400s that a loose test blamed on the code |
| `next/link` in vinext | `ee is not a function` at runtime. Use plain `<a>` |

## 4. Bank formats

| Bank | Format | Narration | Verified |
|---|---|---|---|
| **SBI** | CSV | `UPI/DR/<ref>/<NAME>/<BANK>/<vpa>/Paid` — slashes, hard-wrapped mid-token | 17 rows, 0 warnings |
| **HDFC** | `.xlsx` | `UPI-<NAME>-<vpa>-<IFSC>-<ref>-<note>` — hyphens; also `NEFT CR-`, `ACH D-`, `IB BILLPAY DR-` | 172 rows, 0 warnings |

Two quirks worth remembering: SBI wraps text mid-token with a newline plus one
space (`smohanes\n h1` is `smohanesh1`), and a hyphen *inside* an HDFC VPA
splits the segment, so the payee is the nearest segment **with a space**.

**The running-balance column is the checksum.** Zero warnings on a real file
means every amount was read correctly. It is the strongest signal available and
it is free.

## 5. Working style

- Ponytail mode: the laziest thing that actually works. Read the whole flow
  first, then pick the highest rung that holds.
- Deployment ends with `cd /var/www/projects/Financial-App && ./deploy/deploy.sh`
  — never a `git push` command.
- Verify against the live site when a bug is reported. Twice now the diagnosis
  came from reading the browser's IndexedDB or paging the live API, not from
  guessing at the source.
- Say what was skipped. A half-fix reported as complete is worse than no fix.

## 6. Open questions

| Question | Blocked on |
|---|---|
| Is Paisa staying private, or becoming a product? | Changes the public pages, the tenancy model and the Play Store path |
| Should refunds reduce spending or add to income? | A definition, not code |
| Should savings leave "Spent" entirely? | Currently transfers do; expense-typed investments do not |
| Which PDF layout should the parser target? | One real password-protected statement |
