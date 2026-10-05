# ✅ Tasks & Progress

**Paisa — Household Finance Platform**

This document tracks what is shipped, what is next, and who owns each step.

> **Last reviewed** 2026-10-05 · `TODO.md` at the repo root is the working
> checklist — if the two disagree, **`TODO.md` wins**

---

## 1. Where We Are

```mermaid
flowchart LR
    P1("✅ Phase 1<br/>Ledger & dashboard")
    P2("✅ Phase 2<br/>Statement capture")
    P3("🟡 Phase 3<br/>Android SMS capture")
    P4("⛔ Phase 4<br/>Reconciliation")

    P1 --> P2 --> P3 --> P4

    classDef done fill:#d1fae5,stroke:#10b981,stroke-width:2px,color:#064e3b
    classDef part fill:#fef3c7,stroke:#f59e0b,stroke-width:2px,color:#78350f
    classDef todo fill:#e5e7eb,stroke:#9ca3af,stroke-width:2px,color:#374151

    class P1,P2 done
    class P3 part
    class P4 todo
```

| Phase | Scope | State |
|---|---|---|
| **1 — Ledger & dashboard** | Books, roles, transactions, categories, rules, audit | ✅ Live |
| **2 — Statement capture** | CSV + Excel import, budgets, accounts | ✅ Live |
| **3 — Private capture** | Android SMS capture, background upload, push | 🟡 Written, not shipped |
| **4 — Reconciliation** | Match SMS against statements, flag look-alikes | ⛔ Not started |

```text
Phase 1  ██████████████████████████████  100%
Phase 2  ██████████████████████████░░░░   85%   PDF import outstanding
Phase 3  ████████░░░░░░░░░░░░░░░░░░░░░░   25%   code exists, never run in prod
Phase 4  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
```

> **Health** — 57 tests passing · lint clean · typecheck clean · 5 migrations applied · 0 npm advisories

---

## 2. Done

| Area | Shipped |
|---|---|
| 📒 **Ledger** | Full edit of any entry · void · split · comments · pagination beyond 100 · month navigation |
| 📄 **Import** | CSV and `.xlsx` on one pipeline · SBI and HDFC narrations · balance checksum · per-row dedupe · 2,000-row cap |
| 📅 **Pay cycles** | A book's month follows payday, not the calendar · per-book start day 1–31, clamped in short months · window shown beside the month name |
| 💰 **Money model** | Spent / Saving / Balance · breakdown covering uncategorized, splits and transfers · account-to-account flows |
| 🎯 **Budgets** | Percentage of expected income per group · 50/30/20 preset · expected income from recurring plans |
| 🔁 **Recurring** | Self-posting when due · month-end sticky · catch-up after downtime · idempotent |
| 🏠 **Tenancy** | Isolated workspaces · invitations · self-provisioning (flagged off) |
| 🔒 **Security** | Full-codebase audit; all High and Medium findings fixed |
| 🚀 **Ops** | One-command deploy · backed-up migrations · scoped ledger reset |
| 🛡️ **Master admin** | `/admin` — every account, add · rename · disable · reset password · back up · clear · **reset to new** · delete · the **access-request waiting list** |
| 🌐 **Public** | Landing page at `/` · sign-in moved to `/login` · 13 information pages · one shared header and footer · **Request access** popup that files a row instead of opening an email |

---

## 3. Next — Android on a Real Phone

> The new app is planned phase by phase in `Mobile App/`. **Phase 0 is done**
> (project, API client, theme, 50 tests, runs on the emulator). Task 1 below is
> still the gate for signing in to production; its exact steps are in
> `Mobile App/05-firebase-android-setup.md`. Tasks 2–3 are absorbed by the new
> app's Phase 1; tasks 4–7 belong to its Phase 9 (SMS capture), after v1.

Nothing below is verifiable until real SMS from real banks is flowing.

| # | Task | Owner | Blocks |
|---|---|---|---|
| 1 | Register the Android app in Firebase; add `google-services.json` | 👤 **Arjun** | Everything — the app cannot authenticate |
| 2 | Replace hardcoded `bookId` + dev-auth header with real book selection and an ID token | 🤖 Claude | Every upload 404s today |
| 3 | Point the build at production via `--dart-define` | 🤖 Claude | — |
| 4 | Collect 10–20 real bank SMS, redacted | 👤 **Arjun** | The parser has 3 invented fixtures |
| 5 | Background upload — WorkManager + `BOOT_COMPLETED` | 🤖 Claude | The "under a minute" goal |
| 6 | Play Store restricted-permission declaration | 👤 **Arjun** | Weeks of lead time — start now, in parallel |
| 7 | Consolidate the duplicated Kotlin/Dart parsers | 🤖 Claude | They will drift |

> ⚠️ `google-services.json` and `firebase_options.dart` are both **missing**.
> **Task 1 is the gate on the entire phase.**

---

## 4. Then — Close the Capture Loop

| Task | Note |
|---|---|
| Push notification on `pending_review` | The worker's handler is a stub and no Redis runs. The API's own `setInterval` is probably the right home |
| Reconcile SMS against statement imports | `externalRef` holds the UPI reference on both — the natural key |
| Flag look-alike duplicates | Same merchant, amount and day. **Flag, never merge** |

---

## 5. Smaller, Worth Doing

| Task | Why it matters |
|---|---|
| **Speed up deploys** | `npm ci` rebuilds `node_modules` twice every deploy. Plan: stamp the lockfile hash, skip when unchanged |
| **Publish a real contact address** | `CONTACT_EMAIL` is still a placeholder on the contact page. **Request access** no longer needs it — it is a form now |
| **Apache on the droplet sends 2 of 6 security headers** | The repo's vhost is not the live one. No CSP, `X-Frame-Options`, HSTS or `Permissions-Policy` on any dashboard response |
| **Seven mutations write no audit event** | Including every SMS the Android app will upload. Decide before the phone starts posting |
| **Unknown paths return 200, not 404** | The `[slug]` route renders a not-found body with a success status |
| **Click Approve once on the live site** | 👤 Arjun's step — the Firebase half of approving a request has no service account on the dev machine, so only the new email lookup could be verified against the live project |
| **Install the Firebase service-account key** | 👤 Arjun's step — without it the admin page cannot list, add, rename, disable or reset Firebase accounts |
| **Prune expired `IdempotencyRecord` rows on a schedule** | A ledger wipe now clears the orphans, but nothing clears the expired ones |
| **A real illustration for the landing hero** | Three CSS blobs stand in for the leaf illustration in the Figma file |
| **PDF import** | Blocked on one real sample — row detection is shaped entirely by a bank's layout |
| **Refunds are invisible** | `kind: 'refund'` appears in no tile. Decide the definition first |
| **Drop per-category budgets** | Superseded by the group plan; endpoints still exist unread |
| `GET /transactions/:id` | Reading one entry means listing and filtering client-side |
| Recurring "last working day" | Month-end is sticky and correct, but holidays need a calendar. Less pressing now — pay cycles no longer depend on predicting the exact date |

---

## 6. Before Enabling `TENANT_SELF_PROVISION`

| # | Task | Owner |
|---|---|---|
| 1 | **Disable public sign-up in Firebase** — Auth → Settings → User actions | 👤 **Arjun** |
| 2 | Let a household rename its books | 🤖 Claude |
| 3 | A way to disable a user from the dashboard | 🤖 Claude |

> Without step 1, the web API key is enough for anyone to register themselves a
> household. **That setting is the only real control.**

---

## 7. Security Backlog

All High and Medium findings from the 2026-09-09 audit are fixed. These remain:

| Finding | Severity |
|---|---|
| 403s name the role (`Role viewer cannot edit`) | 🟢 Low |
| Emails written to the journal during provisioning | 🟢 Low |
| No way to disable a user | 🟢 Low |
| Nothing prunes expired `IdempotencyRecord` / `Attachment` rows | 🟢 Low |
| Self-provisioning rate-limited only by the global 120/min per IP | 🟢 Low |
| CSP carries `script-src 'unsafe-inline'` — vinext emits ~16 nonce-less inline scripts | 🟢 Low, accepted |

---

## 8. Known Data Quirks in the Live Books

| Book | Quirk |
|---|---|
| `book_owner` | `BOAZ M R +₹5,000` is typed `transfer`, so it is excluded from Income. Retype if it was a repayment |
| `book_owner` | The ₹1,04,178 Salary was entered by hand; no matching credit is in the statement window. Void it once capture runs |
| Jadheer's book | 172 HDFC rows, all August. Use **‹** to reach them — the dashboard opens on the current month |
