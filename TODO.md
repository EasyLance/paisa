# Paisa — outstanding work

Ordered by what unblocks the most. Last reviewed 2026-10-24.

## Now: turn on the nightly backup

- [ ] **Install the `deploy/backup.sh` cron job on the droplet.** *Arjun's
      step.* Built 2026-10-24: a nightly gzipped dump into `dbbackup/` in the
      checkout, 14 days kept. Run it once by hand, then add the crontab line
      (both in `docs/architecture.md` §10.1). Until then the only backups are
      the ones `migrate.sh` takes.

## Next: get the Android app onto a real phone

> The replacement app is planned in `Mobile App/` (start at its `README.md`).
> **Phases 0 to 3 are built** (2 is the live dashboard, 3 the ledger). Arjun has confirmed on a real
> phone: production sign-in, the fingerprint lock, adding a payment and importing a statement.
> What is left on them is reviewing real payments on the phone (`Mobile App/docs/tasks.md`). Phase 4 (statement import) is built for .xlsx, CSV and
> password-protected PDF, all opened on the phone (the PDF reader has only seen synthetic
> statements: try a real bank PDF). Phase 5 (budgets and recurring) is built; its gate is a
> plan saved on the phone appearing unchanged on the web. The
> hardcoded-book and parser items below describe the older `apps/mobile` app and
> are replaced by that plan rather than fixed here.

The app is written and never run against production. Everything below is
guesswork until real SMS from Arjun's own banks is flowing.

- [x] **Register an Android app in Firebase** — *done 2026-10-05* for the new
      app in `Mobile App/` (`google-services.json` is in place and Firebase
      initialises; no `firebase_options.dart` is needed). Original note: The
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

## From the pre-mobile audit (2026-10-03)

Nine bugs found and fixed in the same pass — see `docs/memory.md` §3. These
four are left because they are your call or they are the host, not the code:

- [x] **The live Apache sent two of the six security headers.** *Done
      2026-10-24*: the other four (`X-Frame-Options`, `Permissions-Policy`,
      HSTS, CSP) were added by hand after line 33 of
      `/etc/apache2/sites-available/zz-paisa-le-ssl.conf`, the live 443 vhost.
      Checked afterwards: all six on every response, sign-in, the dashboard,
      month changes and `/admin` work with no CSP violations, and
      `easylancefreelance.com` got none of them. The live vhost is still not
      `deploy/paisa-apache.conf` — same drift as the systemd units.
- [ ] **Seven mutations write no audit event** — accounts, categories,
      categorization rules, recurring plans, ingestion events, imports and
      `PATCH /me`. Both stores agree, so it is a gap, not drift. It matters most
      for ingestion: **every SMS the Android app uploads will be invisible in the
      audit trail**. Decide whether `IngestionEvent` + `TransactionSource` is
      provenance enough, or add the rows, before the phone starts posting.
- [x] **An unknown path returns HTTP 200.** *Done 2026-10-24*: `[slug]` calls
      `notFound()` and `app/not-found.tsx` renders the same copy with a real
      404, for nested paths too. `/robots.txt` and `/sitemap.xml` were falling
      into the same catch-all as HTML; they are now `app/robots.ts` and
      `app/sitemap.ts`, the sitemap built from `siteNav`. Live after the next
      deploy.
- [ ] **Format the new mobile app, then restore CI's format step.** CI now
      checks `Mobile App/app` (analyze + 380 tests) instead of the old app, but
      `dart format` would rewrite 64 of its files, so that step was dropped.
- [ ] **`Idempotency-Key` is required but its value is ignored in production.**
      Only the memory store reads it; `prisma-store` dedupes on the unique
      `(workspaceId, sourceHash)`. Harmless today — `sourceHash` is the right
      key for SMS — but the header is theatre, so either use it or stop
      demanding it.

## Smaller, worth doing

- [ ] **Deploy the access-request waiting list.** *Arjun's step.* Built
      2026-10-03: the landing page's "Request access" button is now a popup that
      files a row, and `/admin` shows who is waiting with an **Approve** button
      that creates the account and emails the password link. Needs
      `./deploy/migrate.sh` first — it adds the `AccessRequest` table. The
      Approve button's Firebase half could not be exercised locally (no service
      account on this machine); the new `findFirebaseUserByEmail` call was
      verified read-only against the live project, and everything else in that
      path is already in production use. **Click it once on the live site and
      confirm the account appears in Firebase.**

- [ ] **Install the Firebase service-account key.** *Arjun's step.* Without it
      `/admin` can back up, clear and delete ledger data, but cannot list
      Firebase accounts, add a user, change an email, disable an account or send
      a password reset. Firebase console → Project settings → Service accounts →
      *Generate new private key*, then on the droplet:

      **Done 2026-10-02** — key at `/etc/paisa/firebase-admin.json`, `600
      elance:elance`; `PLATFORM_ADMINS` and `FIREBASE_SERVICE_ACCOUNT_FILE` in
      `/var/www/projects/Financial-App/paisa.env`. Verified against the live
      project: list, create, rename, disable, delete and reset all work.

- [ ] **Rotate that service-account key.** It was pasted into a chat transcript
      on 2026-10-02 (`~/.claude/projects/-Users-arjunmohanesh-Desktop-Financial-App/`),
      so it exists in plaintext in a log file. Generate a replacement in the
      Firebase console, repeat the install, then delete key `6bc84ba7…` under
      **Project settings → Service accounts → Manage keys**.
- [ ] **Reconcile `deploy/` with the live droplet.** The units and
      `bootstrap.sh` name a `paisa` service user and `/etc/paisa/paisa.env`;
      the host runs as `elance` with the env file in the app directory. As it
      stands `bootstrap.sh` cannot rebuild this server. See *Live host drift*
      in `CLAUDE.md`.

- [ ] **Publish a real contact address.** `CONTACT_EMAIL` in
      `apps/web/app/site-pages.ts` is still the placeholder
      `hello@easylancefreelance.com`, and the landing page's **Request access**
      button sends every visitor to `/contact-us`, where that address is the
      only way in. Arjun's step: pick the address you want listed publicly.
- [ ] **A real illustration for the landing page.** The hero currently uses
      three soft CSS blobs where the Figma file has a leaf illustration
      (`design/landing-page/paisa-landing-desktop.png`). Export it as an SVG into
      `apps/web/public/` and drop it bottom-left behind the trust points.

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
- [ ] **PDF statement import.** CSV and .xlsx are parsed and posted; a PDF is
      still only fingerprinted, and the API now says so instead of accepting it
      silently. Needs: `pdfjs-dist` for text extraction (it takes a `password`
      for encrypted files), a password field on the import dialog, and a step
      that turns positioned text runs back into table rows before handing them
      to `parseStatementRows`. **Blocked on a real sample** — the row-detection
      is entirely shaped by one bank's layout, and writing it blind is how you
      get a parser that works on nothing.
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

## Security audit 2026-10-24

Four reviews (API, statement import, web, Android) plus live probes. Fixed on
2026-10-24, live after the next deploy, each with a test that fails on the old
code:

- [x] **A 376-byte .xlsx crashed the API**, a 2 MB zip bomb inflated to 2.7 GB,
      and three regexes went quadratic. `xlsx.js` / `statement.js` now bound
      columns, entries, inflated size and text length (`docs/architecture.md` §7).
- [x] **One rate-limit bucket for the whole internet.** Fastify 5 ignored
      `TRUST_PROXY_HOPS`; now `trustProxy: 'loopback'`.
- [x] **Admin gate trusted an unverified token email.** Now a verified email or a uid.
- [x] **A spouse could read a private book's payment** by reposting its `sourceHash`.
- [x] **`grantAccess` reused a pre-registered unverified Firebase account.**
- [x] **Negative debits, absurd amounts and impossible dates** in a statement.
- [x] **`npm audit`**: API 0 advisories (Fastify 5.12.7, Zod 4.6.7); web `next`
      16.4.3. What remains is Firestore → `@grpc/grpc-js`, which is not in the
      bundle, and whose only "fix" is a Firebase downgrade.

Your steps:

- [ ] **Get back into `/admin`** — it happened: after the deploy the page said
      "Not a master admin", because the email now only counts once Firebase
      has verified it and this account never was. Either add the uid to the
      live `paisa.env` (`PLATFORM_ADMINS=arjunm295707@gmail.com,<uid>`, then
      restart `paisa-api`), or deploy the follow-up and use the page's **Send
      verification email** button. Verifying is the better end state: it also
      makes the email a real proof of ownership.
- [ ] **Drop `TRUST_PROXY_HOPS` from the live `paisa.env`.** It is ignored now.
- [ ] **Disable public sign-up in Firebase** (below) — it is the precondition
      for the admin-gate and pre-registration attacks this audit fixed.

Still open from this audit:

- [ ] **Android release is signed with the debug key**, `allowBackup` defaults
      on, and R8 is off (`Mobile App/app/android/app/build.gradle.kts`). Medium.
- [ ] Low, API: a reviewer can create rules through `reclassify` with
      `applyToFuture`; an owner accepting their own invite leaves the book with
      no owner; `counterAccountId` is not scope-checked on create; 500s echo
      Prisma codes; `amountMinor`, `metadata` and the invitation email have no
      size cap on the routes; every route takes 5 MB and parses before auth;
      `POST /v1/access-requests` says whether an email has access; admin delete
      of a Firebase-only user skips `confirmEmail`; ID tokens are not
      revocation-checked; `/docs` (swagger) is unauthenticated, hidden only by
      Apache; recurring plans post as the owner and their creation is unaudited.
- [x] **The dashboard loaded everything twice on first open** — *fixed
      2026-10-24*: 26 API calls became 13. `refresh` records the
      `book|month` it loaded (`loadedKey`) and the effect skips that pair, so
      setting the resolved book no longer re-runs it. Checked in a local build:
      first open, a month change and a book switch each make 13 calls, none
      repeated. A higher global limit for households on one IP is still open.
- [x] **React hydration error #418 on `/`** — *fixed 2026-10-24*:
      `returning()` is read through `useSyncExternalStore` with a server
      snapshot of `false`. A local build with the old code threw the same #418
      as production; the fixed build throws nothing.
- [x] **`/constructor`, `/__proto__`, `/toString` were 500s** — *fixed
      2026-10-24*: `[slug]` looks pages up with `Object.hasOwn`; all now 404.
- [ ] Low, web: `invitationToken()` also accepts `?invite=`, which reaches the
      Apache log.
- [ ] Low, Android: `API_URL` is not forced to https in release; the Excel
      decryption `spinCount` is unbounded; the statement-password field lacks
      `enableIMEPersonalizedLearning: false`.

## Security backlog (the Low findings from the 2026-09-09 audit)

- [ ] **403s name the role** — `Role viewer cannot edit` in `permissions.js`.
      Minor disclosure; make the client-facing message generic.
- [ ] **Emails are written to the journal** during provisioning decisions.
- [ ] **No way to disable a user.** `UserProfile.disabledAt` is checked on every
      request but nothing ever sets it, so revoking someone means SQL or the
      Firebase console.
- [ ] **Nothing prunes expired rows.** `IdempotencyRecord.expiresAt` and
      `Attachment.expiresAt` are set and never acted on.
- [ ] **Self-provisioning is rate-limited only by the global 120/min per IP.**
      Matters once `TENANT_SELF_PROVISION` is on.
- [ ] **CSP carries `script-src 'unsafe-inline'`** because vinext emits ~16
      inline scripts with no nonce. If vinext gains nonce support, tighten it —
      today the CSP is a clickjacking/exfiltration control, not an XSS backstop.

## Known data quirks in the live book

- `BOAZ M R +₹5,000` is typed `transfer`, so it is excluded from Income. If it
  was a repayment or gift, retype it as Income or Refund.
- The ₹1,04,178 Salary was entered manually; no matching credit appears in the
  1–7 Sept statement window. Once capture runs, the bank's own credit will
  arrive and the manual row should be voided.
