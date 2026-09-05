# Paisa production connection guide

The application code and database migrations are checked in. Production activation is configuration-only: provision the external services, supply their credentials as environment variables, migrate MySQL, and deploy the existing API, worker, dashboard, and Android builds.

## 1. MySQL and supporting services

Provision MySQL 8 in an India region with encryption, automated backups, and point-in-time recovery. Set `DATABASE_URL` to its TLS connection string. Provision Redis 7 for BullMQ and set `REDIS_URL`. Statement and receipt workflows use S3-compatible encrypted object storage; set the `OBJECT_STORAGE_*` values from `.env.example`.

Apply the checked-in migrations without creating new migration files:

```bash
npm ci
npm --workspace @paisa/api run prisma:generate
npm --workspace @paisa/api run prisma:deploy
```

Seed the first invite-only household after replacing the three `SEED_*` Firebase UIDs and emails:

```bash
npm --workspace @paisa/api run seed
```

The seed creates users, books, memberships, and editable category suggestions. It does not create example financial amounts.

## 2. Firebase

Create separate Firebase projects for development, staging, and production. For production:

- Enable Email/Password authentication, email verification, password reset, and the chosen MFA policy.
- Register the web app and set all `NEXT_PUBLIC_FIREBASE_*` values in `apps/web/.env.example`.
- Register the Android app ID `com.paisa.mobile` and run the standard FlutterFire configuration flow.
- Enable App Check for web and Android, then set `FIREBASE_PROJECT_ID`, `FIREBASE_PROJECT_NUMBER`, and the comma-separated `FIREBASE_APP_IDS` on the API.
- Keep `AUTH_MODE=firebase` and `APP_CHECK_MODE=enforce`. The production API refuses development authentication.

Invitations are email-bound and expire after seven days. A new recipient can create a Firebase account from the invitation screen, verify the email, sign in, and accept the book grant. Invitation tokens remain in the URL fragment so they are not sent in HTTP requests or hosting logs.

## 3. API and dashboard wiring

Set the API values:

```text
NODE_ENV=production
AUTH_MODE=firebase
APP_CHECK_MODE=enforce
CORS_ORIGINS=https://your-dashboard.example
TRUST_PROXY_HOPS=1
DATABASE_URL=mysql://...
REDIS_URL=rediss://...
```

Set the dashboard's `NEXT_PUBLIC_API_URL` to the public HTTPS API origin and fill its Firebase web values before building. Do not include a trailing slash in the API URL.
Keep `NEXT_PUBLIC_DEMO_MODE=false` in every live environment. The private hosted preview is built with the explicit `build:demo` script; live builds never fall back to sample data when the API is unavailable.

Use the checked-in Dockerfiles for the API and worker. Configure the platform liveness probe as `/health` and readiness probe as `/ready`. Run at least two API instances behind HTTPS, keep the worker as a separate service, and route logs to a sink that preserves the configured redaction.

## 4. Launch gate

Run these checks with Node.js 22 or newer:

```bash
npm test
npm run lint
npm run build
npm audit --omit=dev
DATABASE_URL=mysql://validation:validation@localhost:3306/validation npx --workspace @paisa/api prisma validate
```

Then verify the owner, spouse, and CA end-to-end flows in staging: private-book isolation, invitations, role changes, transaction categorization, budget updates, period verification, audit events, CSV export, token expiry, App Check rejection, and database backup restoration.

The hosted credential-free preview intentionally shows labeled sample data. Once `NEXT_PUBLIC_API_URL`, Firebase web configuration, and the production services above are supplied, the same build switches to authenticated live data.
