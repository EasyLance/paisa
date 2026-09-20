# Paisa — Coding Rules

> Every rule here exists because breaking it cost us something.
> **Last reviewed** 2026-09-20 · Operational rules live in `/CLAUDE.md`

---

## The short version

| # | Rule | Cost of breaking it |
|---|---|---|
| 1 | Money is integer paise, never a float | Rounding errors in a ledger |
| 2 | Shared behaviour goes in `src/domain/` | The two stores silently disagreed |
| 3 | Every mutation writes an audit event | No way to answer "what did this used to say" |
| 4 | Non-trivial logic leaves one runnable check | A bug ships twice |
| 5 | Verify before you claim done | Saying "fixed" about something that isn't |
| 6 | Read the whole flow before the smallest diff | A confident fix in the wrong place |

---

## 1. Money

```js
// ✅  paise as a string over the wire, BigInt in the store
{ amountMinor: '-190100', kind: 'expense' }

// ⛔  never
{ amount: -1901.00 }
```

| Rule | Why |
|---|---|
| Expenses **negative**, income and refunds **positive** | The sign carries direction |
| `kind` and `amountMinor` change **together** | Otherwise income keeps an expense's sign |
| `transfer` keeps the direction it had | A transfer out is still an outflow |
| Serialise through `jsonSafe()` | `JSON.stringify` throws on `BigInt` |
| Round float input to 2dp at the edge | Excel gives you `79485.149999999994` |

## 2. The domain layer

> **Two stores implement one interface.** `memory-store.js` backs the tests and
> demo mode; `prisma-store.js` backs MariaDB. They have diverged before.

**If both stores need the same answer, the answer lives in `src/domain/`.**

| Question | Module |
|---|---|
| Which rule claims this payment? | `categorization.js` |
| Where did the money go? | `spending.js` |
| What moved between accounts? | `accounts.js` |
| When is this plan next due? | `recurring.js` |
| Can this role do that? | `permissions.js` |
| What do these statement rows mean? | `statement.js` |

Duplicating ten lines across the two stores is not the lazy option. It is two
places to fix and one you will forget.

## 3. History is not optional

| Rule | Detail |
|---|---|
| Every mutation writes an `AuditEvent` | With `before` **and** `after` |
| An imported entry keeps the bank's figure | `TransactionSource.importedAmount` survives every edit |
| Nothing is hard-deleted | Accounts and categories **archive**; entries **void**; only rules — which affect nothing recorded — are deleted |
| Voided entries stay in the ledger | They leave the totals, not the record |

## 4. Tests

- Tests live in **`apps/api/test/api.test.js`**. One file. 57 passing.
- Non-trivial logic — a branch, a parser, a money path — leaves **one runnable
  check**. Trivial one-liners do not.
- **Assert the setup succeeded.** Three imports once returned 400 because an
  idempotency key was 7 characters against an 8-character minimum, and the loose
  assertion blamed the code instead.
- Prefer an invariant to an example: `sum(byCategory) === spent + moved` catches
  more than any single expected number.
- Never commit real financial data as a fixture. Build one in the test.

## 5. Validation & errors

| Rule | Example |
|---|---|
| Validate at the boundary with Zod | `parse(schema, request.body)` |
| A missing membership is **404**, not 403 | 403 confirms the resource exists |
| Error messages say what to do next | *"Split it by month and import each part"* |
| Never return `error.message` on a 500 | Generic `INTERNAL_ERROR` only |
| Log the operator's reason, tell the client nothing | Auth failures, provisioning refusals |

## 6. Security

| Rule | Why |
|---|---|
| Secure defaults. `AUTH_MODE` defaults to `firebase` | A missing env var must never open the door |
| Untrusted text into a CSV goes through `csvSafe()` | `=HYPERLINK(...)` as a merchant name is a formula |
| Never a password on a command line | `ps` is readable by every user on a shared box |
| Never interpolate an argument into SQL | Validate the shape first |
| Cap unbounded work | 2,000 rows per import; one request is not a job queue |
| Security headers belong in Apache | helmet only covers API responses |

## 7. Frontend

| Rule | Detail |
|---|---|
| `apps/web` is **not** an npm workspace | Its own lockfile, its own `npm ci` |
| Dense, single-file style in `page.tsx` | Match it; do not "tidy" it into modules |
| Never render a negative as positive | `money()` returns `−₹69,142`, not `₹69,142` |
| Dates anchor via `dateAt()` | Midnight in the **book's** timezone |
| Labels must be literally true | "Available after spending" was a lie; it is "Balance" |
| Plain `<a>` over `next/link` | vinext's Link prefetch throws at runtime |

## 8. Before you say it is done

```bash
npm run test                       # 57 API tests
npm run lint                       # all three JS packages
cd apps/web && npx tsc --noEmit    # dashboard types
# and a build, with the Firebase env sourced
```

A stale `apps/web/dist` looks like a successful build while serving old code.
`rm -rf dist .vinext` first, every time.

## 9. Comments

Comment the **why**, never the what. A comment that explains a line you can read
is noise; one that explains a decision you would otherwise undo is the point.

```js
// ✅
// A plan that falls on the last day of its month means "month end", so it must
// stay at month end. Clamping alone drifts backwards and never recovers:
// 31 Jan would become 28 Feb, then 28 Mar, then 28 Apr.

// ⛔
// Get the last day of the month
```

Mark a deliberate shortcut with `ponytail:` and name its ceiling.

## 10. Scope

Do the task asked. If you find a real problem with it, say so in a sentence and
keep building. Deliver the whole thing or say plainly what you left out — a
half-fix reported as complete is worse than no fix.
