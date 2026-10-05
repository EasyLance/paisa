# 🔎 Findings

**Paisa Mobile — Android app**

Things found while reading the code and this Mac that change, or could change,
how the mobile app is built. Each one says where it was found, why it matters,
and what happens next. Add to the bottom as new ones turn up; mark one **Resolved**
rather than deleting it.

> **Last reviewed** 2026-10-05

| # | Finding | Status |
|---|---|---|
| F1 | App Check vs sideloaded builds | Open — decision recorded |
| F2 | Push notifications are the only server change | Open — Phase 7 |
| F3 | `CLAUDE.md` is wrong about `Idempotency-Key` | Open — doc fix pending |
| F4 | No month filter on the transactions list | Open — measure in Phase 3 |
| F5 | Sideload and Play builds can't update each other | Open — Phase 8 |
| F6 | Android command-line tools missing on this Mac | Open — Arjun's step |
| F7 | Xcode is not installed | Parked until Phase 10 |
| F8 | No system Java on `PATH` | Worked around |
| F9 | Light chart colours are under 3:1 against a white card | Open — mitigated |
| F10 | `GET /memberships` returns every member's `firebaseUid` | Open — Phase 6 |
| F11 | "Confirm" is a category change, not a state change | Resolved |
| F12 | Geist is `.woff2` on the web; Flutter needs `.ttf` | Open — optional |
| F13 | `google-services.json` was one folder too high | Resolved |
| F14 | Web month label is wrong for pay-cycle start days 29–31 | Open — task raised |
| F15 | An outgoing transfer lands in "Other" until it is categorised | Open — Phase 3 decision |

---

## F1 · App Check vs sideloaded builds

**Where:** `apps/api/src/plugins/auth.js` — `APP_CHECK_MODE` defaults to
`enforce` in code; `deploy/paisa.env.example` sets it to `off`.

**Why it matters:** with App Check enforced, every request needs an
`X-Firebase-AppCheck` token. On Android that token comes from the Play Integrity
provider, and Play Integrity does not attest an APK installed outside the Play
Store. Turning enforcement on would lock the sideload channel out of the API.

**Decision:** keep `APP_CHECK_MODE=off` for the mobile launch. Do not call
`FirebaseAppCheck.activate` with Play Integrity in v1.

**Would reverse if:** the app moves to Play-only distribution, or a different
attestation approach is chosen. Record the reversal in `docs/memory.md`.

## F2 · Push notifications are the only server change

**Where:** nothing in `apps/api` stores device tokens or sends FCM. The worker's
`notifications` handler is a stub, and no Redis runs.

**Why it matters:** v1 includes push, so the API gains a table, two routes and a
sender — which means a migration (`./deploy/migrate.sh` before `deploy.sh`) on the
shared droplet.

**Needs from Arjun:** the existing service account carries only *Firebase
Authentication Admin*. Sending needs *Firebase Cloud Messaging API Admin* added
in the console, which widens what that key can do. That is a deliberate call, so
it is not made for you.

**Next:** Phase 7. Design in [`architecture.md`](architecture.md) §8.

## F3 · `CLAUDE.md` is wrong about `Idempotency-Key`

**Where:** `CLAUDE.md` (*Gotchas*) says the header's value is used "only [by] the
memory store". `apps/api/src/store/prisma-store.js` `createTransaction` (around
line 153) hashes the key, looks it up in `IdempotencyRecord`, replays the earlier
transaction for 24 hours, and returns `409 IDEMPOTENCY_CONFLICT` if the same key
arrives with a different body. `TODO.md` repeats the claim.

**Still true:** `POST /ingestion-events` relies on `sourceHash` alone, and
`POST /imports` dedupes per row.

**Why it matters:** the mobile manual-add form can rely on one key per submission,
reused on retry, to make a dropped connection safe. The warning in the repo docs
would have led to needless client-side workarounds.

**Next:** correct `CLAUDE.md` and the matching `TODO.md` item. Not done yet
because those are repo-wide docs; say the word.

## F4 · No month filter on the transactions list

**Where:** `GET /v1/books/:id/transactions` accepts only `state`, `cursor`,
`limit` (max 100).

**Why it matters:** the web filters by month client-side, which is fine on a
laptop. On a phone, "this month's transactions" means paging the whole ledger
(172 rows after one HDFC import, more over time).

**Next:** measure in Phase 3. If paging is slow, add a `month` query using
`periodRangeUtc` from `domain/period.js` so the pay-cycle rule stays in one place.

## F5 · Sideload and Play builds can't update each other

**Why it matters:** the sideloaded APK is signed with the upload key; Play
re-signs with its own app-signing key. Android refuses an update signed with a
different key, so a phone must stay on one channel and uninstall before switching.
Firebase also needs both SHA-1 fingerprints registered.

**Next:** document it for the household in Phase 8, with the build and install
commands for each channel.

## F6 · Android command-line tools missing on this Mac

**Where:** `flutter doctor` reports `cmdline-tools component is missing` and
"Android license status unknown". Licence files do exist in
`~/Library/Android/sdk/licenses`, so builds may work regardless.

**Fix (Arjun):** Android Studio → **Settings → Languages & Frameworks → Android
SDK → SDK Tools** → tick **Android SDK Command-line Tools (latest)** → Apply.
Then `flutter doctor --android-licenses`.

**Status:** Phase 0 proceeds without it. A debug APK built and installed fine
without the tools (2026-10-05), so it is not blocking. If a release build or an
SDK update fails on licences or `sdkmanager`, this is the fix.

## F7 · Xcode is not installed

**Where:** `flutter doctor` — Xcode installation incomplete, CocoaPods missing.

**Why it matters:** only for iOS (Phase 10). Android work is unaffected, which is
why `app/` is created with `--platforms=android`.

**Next:** at Phase 10, install Xcode from the App Store, run
`sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` and
`sudo xcodebuild -runFirstLaunch`, and install CocoaPods.

## F8 · No system Java on `PATH`

**Where:** `java -version` fails; `/usr/bin/java` is only the macOS stub.

**Why it matters:** `keytool` (for signing fingerprints) and Gradle both need a
JDK.

**Worked around:** Android Studio bundles one. Flutter finds it on its own; for
`keytool` use
`"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"`.

## F9 · Light chart colours are under 3:1 against a white card

**Where:** `docs/design.md` §2 group swatches on `#ffffff`. Measured in
`app/test/theme_test.dart`: lifestyle `#a9c467` is about 1.9:1, saving `#df8d6d`
and other `#a1a8a3` sit near 2.5:1. The dark-mode set passes 3:1.

**Why it matters:** WCAG asks 3:1 for graphics that carry meaning by themselves.

**Mitigation:** every segment is also named and valued in a legend, so colour is
never the only carrier (`docs/design.md` §9 already requires this of status).
The test holds a 1.9:1 floor so a swatch cannot fade into the card.

**Would change if:** Arjun wants the phone to be stricter than the web. Darkening
the light swatches is a design call, because it changes the brand palette.

## F10 · `GET /memberships` returns every member's `firebaseUid`

**Where:** `apps/api/src/store/memory-store.js` `listMemberships` spreads the
whole user row into `user`; recorded in `app/test/fixtures/memberships.json`.
The Prisma store is expected to do the same; check in Phase 6.

**Why it matters:** a book owner can read other members' Firebase uids. Low
severity, and the same people can already see their emails, but the uid is an
identifier the screen never needs.

**Next:** the app parses only `id`, `email`, `displayName` and `role`, never logs
the rest. Trimming the response is an API change for Phase 6, alongside the
`TODO.md` security backlog.

## F11 · "Confirm" is a category change, not a state change

**Where:** `prisma-store.js` `updateCategory` writes `state: 'confirmed'` together
with the new category; the web's `setCategory` relies on it.

**Consequence:** a `reviewer` (the CA) *can* confirm payments, by choosing a
category. A bare `PATCH {state: 'confirmed'}` needs `edit` (editor and above), so
the app's Confirm button for a payment that already has the right category should
re-submit that category rather than call the edit route, or be offered to editors
only. Decide in Phase 3 and record it in `docs/memory.md`.

**Resolved** in design §4; the Phase 3 implementation follows it.

## F12 · Geist is `.woff2` on the web; Flutter needs `.ttf`

**Where:** `apps/web/.vinext/fonts/geist-*` holds Next's split `.woff2` subsets.

**Consequence:** Phase 0 uses the system serif and sans. Matching the web exactly
needs the Geist `.ttf` files (open-licensed), which means downloading them: not
done without your say-so. Purely cosmetic; skip unless the difference bothers
you.

## F13 · `google-services.json` was one folder too high

**Where:** it was saved to `app/android/`; the Gradle plugin reads
`app/android/app/`. With the file in the wrong place the build still succeeds and
Firebase simply is not configured, which looks like a runtime failure later.

**Resolved 2026-10-05:** moved to `app/android/app/`; the Gradle plugin now
applies, and a build without `DEV_AUTH` logs `FirebaseApp initialization
successful`. The file names `paisa-easylance`, package `com.paisa.mobile`. Its
`oauth_client` list is empty because it was downloaded before the debug SHA-1 was
added; that does not affect email and password sign-in, and re-downloading
refreshes it.

## F14 · The web's month label is wrong for pay-cycle start days 29–31

**Where:** `apps/web/app/page.tsx` `currentPeriod()` accepts only start days 1–28
(`startDay <= 28 ? startDay : 1`) and does not clamp to the end of a short month.
The API's `currentPeriodLabel()` in `domain/period.js` accepts 1–31 and clamps.

**Evidence:** both functions run over every day of 2026 for nine start days: 3,285
comparisons, 61 mismatches, all at start days 29 (30), 30 (19) and 31 (12), none at
1, 5, 15, 16, 26 or 28. Example, start day 30: 2026-01-30 is `2026-02` to the API
and `2026-01` to the web. The web opens, and its arrows start, one period behind
on those days. The window printed under the label comes from the server, which is
why the header never contradicts the figures.

**Mobile:** the phone ports the API's function, not the web's, and a test checks it
against `test/fixtures/period_labels.json`, recorded from the real `period.js`
across 11 start days, month ends, a leap February and a year end. It agrees on all
1,276 cases.

**Next:** written up for the web in its own file,
[`apps/web/BUG-pay-cycle-month-label.md`](../../apps/web/BUG-pay-cycle-month-label.md)
(cause, evidence, a repro script, the fix and how to verify it), and raised as a
separate task. The fixture is reusable there. `docs/memory.md` already says "Start day clamps, it does not cap".

## F15 · An outgoing transfer lands in "Other" until it is categorised

**Where:** `domain/spending.js` counts an outgoing transfer as money that left but
gives it its category's group, and a transfer has no category until someone sets
one, so it falls under `Uncategorized` in group `Other`. Seen on the recorded
fixture: ₹11,234.50 under Other is a ₹10,000 transfer plus a ₹1,234.50 payment.

**Consequence:** a budget share for the `Saving` group (20% in the fixture) shows
₹0 spent however much has been moved, until the transfer is given a category in
the `Saving` group. The web behaves the same way.

**Next:** not a bug, but easy to misread. Phase 3's review flow lets a reviewer
categorise a transfer; consider whether the transaction detail should say "a
transfer to your own account: choose a Saving category to count it against that
budget".
