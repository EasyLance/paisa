# Paisa — outstanding work

Ordered by what unblocks the most. Last reviewed 2026-09-09.

## Next: get the Android app onto a real phone

The app is written and never run against production. Everything below is
guesswork until real SMS from Arjun's own banks is flowing.

- [ ] **Register an Android app in Firebase** — *Arjun's step.* The
      `paisa-easylance` project only has a web app. Console → Add app → Android,
      package `com.paisa.mobile`, drop `google-services.json` into
      `apps/mobile/android/app/`. Both `google-services.json` and
      `lib/firebase_options.dart` are currently **missing**, so the app cannot
      authenticate at all.
- [ ] **Replace the hardcoded book and dev auth.**
      `lib/services/api_client.dart` posts to `bookId = 'book_arjun'` with an
      `x-dev-user-id: user_owner` header. Production books are `book_owner` and
      `book_home`, and the API rejects the dev header — every upload would fail.
      Needs: fetch `/v1/books`, let the user pick a capture target, persist it,
      and send a real Firebase ID token.
- [ ] **Point the build at production** —
      `--dart-define=API_URL=https://paisa.easylancefreelance.com`.
- [ ] **Collect 10–20 real bank SMS** (redacted) — *Arjun's step.* The parser has
      3 invented fixtures and has never seen an HDFC or ICICI message.
- [ ] **Background upload.** No `WorkManager`, no foreground service, no
      `BOOT_COMPLETED`. Today capture only happens while the app is open, which
      misses the "captured within a minute" goal.
- [ ] **Play Store restricted-permission declaration** for `READ_SMS` /
      `RECEIVE_SMS`. Weeks of lead time — start it early, in parallel. Statement
      import and manual entry are the fallback if approval drags.
- [ ] **Consolidate the duplicated parsers.** `FinancialSmsParser.kt` and
      `lib/services/sms_parser.dart` reimplement the same regexes; they will
      drift. Same argument as `src/domain/` on the API side.

## Then: close the capture loop

- [ ] **Push notification when something lands in `pending_review`.** The
      worker's `notifications` handler is a stub returning
      `queued-for-fcm`, and no Redis is running — so nothing is queued. Given
      the API already runs its own `setInterval` for recurring plans, FCM
      probably belongs there rather than in BullMQ.
- [ ] **Reconcile SMS against statement imports.** Right now a payment captured
      by SMS and then imported from a statement produces two rows. The UPI
      reference is in `externalRef` on both and is the natural match key. Do
      this after a real statement and real SMS can be compared side by side.
- [ ] **Flag look-alike duplicate payments** — same merchant, same amount, same
      day. Flag for review, never merge automatically.

## Smaller, worth doing

- [ ] **Speed up deploys.** `npm ci` deletes and rebuilds `node_modules` on every
      deploy, twice (root workspace + `apps/web`'s own lockfile), even for a
      one-line change. Plan: stamp each `package-lock.json` hash in a gitignored
      `.deploy-stamp/`, skip `npm ci` when it matches and `node_modules` exists,
      same for `prisma generate` against `schema.prisma`, add
      `--prefer-offline --no-audit --no-fund`, and a `--force-install` escape
      hatch. Do **not** switch to `npm install` (drifts from the lockfile) and do
      **not** skip `rm -rf dist .vinext` (that guard exists because a stale cache
      once shipped a bundle with no Firebase config).
- [ ] **Refunds are invisible in the tiles.** `saved = income - spent` ignores
      `kind: 'refund'` entirely, so a refund shows up nowhere. Decide whether it
      reduces spend or adds to income before changing it.
- [ ] **PDF statement import** only fingerprints the file. CSV is parsed and
      posted; PDF text extraction is a much bigger job.
- [ ] **Per-category rupee budgets are superseded** by the group percentage plan.
      `Budget` table and `/v1/books/:id/budgets` still exist and still work, but
      nothing in the dashboard reads them. Drop them once it's clear no rows
      matter.
- [ ] **No `GET /v1/books/:bookId/transactions/:id`.** Reading one transaction
      means listing and filtering client-side.
- [ ] **Recurring plans can't express "last working day".** Month-end is sticky
      and correct, but weekends and holidays need a calendar. A plan due Sat 31
      Oct fires on the 31st, not Fri the 30th.

## Before turning on TENANT_SELF_PROVISION

- [ ] **Disable public sign-up in Firebase** — *Arjun's step.* Authentication →
      Settings → User actions → uncheck "Enable create (sign-up)". Without this,
      the web API key is enough for anyone to register themselves a household.
- [ ] Consider letting a new household **rename its books**. Provisioning names
      them `<Name>'s finances` and `Household`; there is no rename endpoint.
- [ ] A provisioned owner cannot be **removed or disabled** from the dashboard —
      `disabledAt` exists on `UserProfile` but nothing sets it.

## Known data quirks in the live book

- `BOAZ M R +₹5,000` is typed `transfer`, so it is excluded from Income. If it
  was a repayment or gift, retype it as Income or Refund.
- The ₹1,04,178 Salary was entered manually; no matching credit appears in the
  1–7 Sept statement window. Once capture runs, the bank's own credit will
  arrive and the manual row should be voided.
