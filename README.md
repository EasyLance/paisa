# Paisa

Paisa is an Android-first household finance platform for India. It combines a Flutter app, a responsive React dashboard, a Fastify REST API, and a MySQL ledger. Financial SMS messages are parsed on-device; only normalized transaction fields are queued for upload.

## What is implemented

- Private owner and spouse books plus an explicitly shared household book.
- Owner, editor, reviewer/CA, and viewer authorization enforced by the API. Owners can change a member's role, promote a co-owner, remove access, and revoke a pending invitation; a book always keeps at least one owner and nobody can change their own access.
- Immutable transaction sources, integer-paise money values, categorization, splits, comments, budgets, recurring plans, imports, period verification, and append-only audit events.
- Idempotent SMS/statement ingestion with workspace-level source hashes.
- Interactive React dashboard with overview, transaction search/review, budgets, reports, CSV exports, book switching, member roles, invitation acceptance, period verification, and audit history.
- Dashboard reviewer workflow: split a captured payment across categories, post audited review notes on a transaction, and confirm categories with an optional merchant rule for future payments.
- Dashboard configuration: financial accounts, workspace categories, merchant/VPA categorization rules, and recurring plans are each editable and removable in place, plus duplicate-safe CSV/PDF statement imports fingerprinted in the browser.
- Removal preserves history: accounts and categories are archived rather than deleted, recurring plans are stopped, and only rules — which affect nothing already recorded — are deleted outright. Every change is audited.
- Flutter Android overview, SMS permission onboarding, native financial-message parser, encrypted offline queue, retrying REST upload, and Firebase bootstrap.
- MySQL Prisma schema, checked-in initial migration, production seed, Redis/BullMQ workers, OpenAPI documentation, and local demo mode.

The screenshots supplied for planning influenced the seed category names only. Their sample financial amounts are not written to the production database.

## Repository

```text
apps/web       React dashboard (Vinext/Vite)
apps/api       Fastify REST API and Prisma schema
apps/worker    BullMQ background workers
apps/mobile    Flutter Android application and Kotlin SMS bridge
```

## Local start

Requirements: Node.js 22+, Flutter 3.38+, MySQL 8, Redis 7, and Java 17 for Android builds.

1. Copy `.env.example` to `.env` and keep `AUTH_MODE=dev` for the local demo.
2. Start MySQL and Redis with `docker compose up -d` or equivalent local services.
3. Install JavaScript packages with `npm install` and Flutter packages with `flutter pub get` inside `apps/mobile`.
4. Apply the database with `npm run prisma:migrate`, then seed invite-only pilot users with `npm --workspace @paisa/api run seed`.
5. Run the dashboard with `npm run dev`, the API with `npm run serve`, and the optional background worker with `npm run dev:worker`. The dashboard expects the API on port 4000, so start both in separate terminals.
6. Run Flutter with `flutter run --dart-define=API_URL=http://10.0.2.2:4000` from `apps/mobile`.

The API automatically uses a seeded in-memory store when `DATABASE_URL` is absent. This makes the dashboard and automated tests runnable without external credentials; production must set `DATABASE_URL`, `AUTH_MODE=firebase`, and `APP_CHECK_MODE=enforce`.

## Firebase and Android release setup

- Create separate Firebase projects for development, staging, and production.
- Enable the desired invite-only authentication providers and MFA policy.
- Register the Android application ID `com.paisa.mobile`, add the generated Firebase configuration through the standard FlutterFire flow, and run with `--dart-define=FIREBASE_ENABLED=true`.
- Configure the production API with the Firebase project ID, project number, and allowed app IDs. ID and App Check tokens are verified against Google's rotating public keys, so no Firebase service-account key is required by the API.
- Register release signing through a private keystore before producing a Play Store bundle.
- Complete Google Play's SMS permissions declaration. The application remains usable through manual entry and statement imports if permission is denied.

The exact production connection sequence, required environment variables, migration command, health probes, and launch checks are in [Production setup](docs/PRODUCTION_SETUP.md). No source-code edits are required to connect MySQL or Firebase.

## Verification

```text
npm test
npm run lint
npm run build
cd apps/mobile && flutter analyze && flutter test
```

API documentation is available at `/docs` while the server is running. `/health` is the liveness probe and `/ready` verifies datastore connectivity. Demo requests may use `x-dev-user-id` with `user_owner`, `user_spouse`, or `user_ca`; that mode is refused by the production deployment configuration.

All amounts shown by the credential-free demo are illustrative pilot data. Production seeding creates only users, books, memberships, and editable category suggestions.

## Production boundaries

Paisa does not initiate payments, store UPI PINs or banking passwords, calculate tax, file taxes, lend money, or execute investments. Account Aggregator connectivity and public billing remain post-pilot work.

Known gap: the web sign-in supports email, password, password reset, and invited-account creation, but it cannot yet complete a multi-factor challenge. MFA must stay unenforced in Firebase until that flow is built.
