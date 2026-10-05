# 🧠 Project Context

**Paisa Mobile — Android app**

The things you cannot read off the code: decisions and their reasons, the traps
already paid for, and what would make us change our minds. The platform's own are in
the repo's [`docs/memory.md`](../../docs/memory.md).

> **Last reviewed** 2026-10-05 · Working rules live in [`rules.md`](rules.md) and the
> repo's `/CLAUDE.md`. `/CLAUDE.md` wins any disagreement.

---

## 1. Facts

| | |
|---|---|
| **Application ID** | `com.paisa.mobile` — permanent once on Play |
| **Firebase** | Project `paisa-easylance`; the Android app is registered (project number `505038559840`); `google-services.json` is at `app/android/app/` |
| **Production API** | `https://paisa.easylancefreelance.com` (Apache fronts the dashboard and `/v1`) |
| **Toolchain** | Flutter 3.38.5, Dart 3.10.4. Android SDK platforms 34–36. Emulator `Medium_Phone_API_36.1` |
| **JDK** | None on `PATH`. Android Studio's is at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`; Flutter and Gradle find it, `keytool` needs the full path |
| **Debug SHA-1** | `5E:4D:10:4B:D1:C8:CE:A9:D7:52:A6:3F:BB:37:99:AC:68:AE:F4:AA` (a development key, not a secret) |
| **Missing on this Mac** | Android command-line tools (not blocking); Xcode and CocoaPods (iOS only, Phase 10) |
| **Old app** | `apps/mobile`, left untouched until the new app replaces it. It holds the SMS bridge Phase 9 reuses |
| **Distribution** | A sideloaded APK and Play internal / closed testing. A phone uses one channel only |

### 1.1 Running it

```bash
# the API, in dev auth, with sample data (Node 22+)
export PATH="$HOME/.nvm/versions/node/v26.5.0/bin:$PATH"
cd apps/api && AUTH_MODE=dev HOST=127.0.0.1 PORT=4000 node src/server.js

# the app on the emulator, talking to it, signed in as a dev user
cd "Mobile App/app"
flutter run --dart-define=DEV_AUTH=true            # or DEV_USER_ID=user_ca for the CA
# in the sign-in screen, the "email" box takes a dev user id when DEV_AUTH is on

# against production (a release build: the window is secure, so no screenshots)
flutter run --release --dart-define=API_URL=https://paisa.easylancefreelance.com
```

Dev users in the sample data: `user_owner` (two books, an owner of both), `user_spouse`
(owner of their own book) and `user_ca` (a reviewer on the household book).

---

## 2. Decisions and Why

| Decision | Reason | Would reverse if |
|---|---|---|
| **Flutter** | Already in the repo; one Dart codebase for Android now and iOS later. Only SMS capture is Android-specific, because iOS cannot read SMS | Native Android features dominate and iOS is dropped |
| **A fresh project in `Mobile App/`, not an edit of `apps/mobile`** | The old app's screens were hardcoded sample data, its book id and dev header could not work in production, and it carried a Kotlin/Dart parser duplicate. Starting clean kept only the ideas worth keeping | The old SMS bridge needs little change: port it in Phase 9 rather than rewrite it |
| **SMS capture is Phase 9, after v1** | v1 then asks for no SMS permission, so Play testing needs no restricted-permission declaration (weeks of lead time) | Arjun wants capture before anything else |
| **Android-only `flutter create`; iOS added later** | iOS needs Xcode and an Apple account; nothing in v1 needs it | Phase 10 starts |
| **Only the packages a phase uses** | Each plugin carries Android config and build time; adding all up front would ship unused permissions | — |
| **Riverpod, plain `Navigator`, no code generation** | Few screens, small models. Hand-written models fail loudly and need no build step | Deep links arrive (then `go_router`), or the models grow past a few dozen |
| **`APP_CHECK_MODE=off` for the mobile launch** | Play Integrity does not attest a sideloaded APK, so enforcing App Check would lock the sideload channel out | The app becomes Play-only |
| **The lock is a UI gate over the Firebase session, never a replacement** | Locking does not sign out or change the token, so a forgotten PIN is never a locked-out account. It uses the phone's own screen lock, so there is no Paisa PIN to forget or leak | A requirement appears to lock against someone who knows the phone's PIN |
| **`FLAG_SECURE` on release builds only** | Balances must not show in recents or recordings, but debug builds need screenshots | The household finds the block annoying: make it a setting |
| **The phone ports the API's pay-cycle function, not the web's** | The web's copy is wrong for start days 29–31 (`findings.md` F14). The API is the source of truth, and a recorded table keeps the port honest | The API exposes the current period itself, so nothing needs porting |
| **Month navigation stops at today's period** | Nothing to see beyond it, and the web's habit of opening future months shows only zeros | Someone needs to plan a future month on the phone |
| **"Review" leads to the Activity tab** | The dashboard's review card has to go somewhere. It is a placeholder until Phase 3 | — |
| **The role-abilities card lives in Settings** | It served the Phase 1 gate on the Overview tab; once the dashboard arrived it was clutter, but it still explains why a button is missing | — |
| **An error replaces the figures** | A zeroed screen beside an error reads as "nothing happened", and old numbers read as live | — |
| **Dev auth takes a typed dev user id as the "email"** | One build can be a viewer, a reviewer and an owner without a Firebase account. Compile-time guarded, so a release build cannot reach it | — |
| **The first review headline says "needs"** | The web's "1 payment need a quick review" is a grammar slip | — |
| **Statement import is the iOS capture path** | iOS cannot read SMS, so Phase 4's quality matters more than it looks | — |

---

## 3. Traps Already Paid For

### 3.1 State and tests

| Trap | What happens |
|---|---|
| Riverpod 3 **pauses a provider nothing is listening to** | `container.read(provider.future)` in a test never completes: ten session tests timed out at 30 s. Register `container.listen(provider, (_, _) {})` first. A screen is always listening in the app |
| Riverpod 3 **retries a failed provider on its own** | A failed `/me` lookup would hit the API again and again before showing its error. `retry: (count, error) => null` on the `ProviderScope` and on test containers |
| A provider that reads `bookProvider()!` | During sign-out the session has no book for a moment while the dashboard is still on screen, so `!` throws inside Riverpod. Pass the book's values in as the provider's argument |
| Riverpod 3 family notifiers take their argument in the **constructor** | `NotifierProvider.family<MonthController, String, Key>(MonthController.new)` with `MonthController(this.key)` |
| `Override` is not exported by `flutter_riverpod` | Import `package:flutter_riverpod/misc.dart show Override` in test helpers |
| `tester.scrollUntilVisible` stops when the widget is *built* | A list builds items beyond the viewport, so it returns without scrolling and the next `tap` misses. Use `ensureVisible` then `pumpAndSettle` |
| A test finder matching a field behind a bottom sheet | The sheet's `Email` and the form's `Email` are both on screen. Scope with `find.descendant(of: find.byType(BottomSheet), ...)` |
| The test font is wider than a real one | Ahem makes text overflow in tests where real fonts fit. Treat it as real for long `₹` amounts |
| A test asserting a screen by a greeting that moved | Three tests used "Hello, Arjun" as "we reached home" and broke when the greeting went. Assert on something structural, such as the Settings tooltip |

### 3.2 Layout

| Trap | What happens |
|---|---|
| `ColoredBox` inside a `Row` of fixed height | A chart bar of `Expanded(child: ColoredBox(...))` rendered **nothing**: the row centres its children and a box with no child sizes to zero. `crossAxisAlignment: stretch`. A screenshot found it; the analyzer and tests did not |
| Two cards in a `Row` with different content | Different heights. `IntrinsicHeight` and stretch |
| Two text buttons in one `Row` on 360dp | Overflowed by 226px. Use a `Wrap` |
| A label and a long `₹` pair sharing a row | They do not fit on 360dp. Put the amounts on their own line |
| `ExpansionTile` rows are tall | The default minimum is 56dp; `visualDensity: compact` helps a little. A custom row is the next step if it still looks airy |

### 3.3 Android and Firebase

| Trap | What happens |
|---|---|
| `flutter create` puts `INTERNET` in the **debug** manifest only | A release build has no network. It is in the main manifest; cleartext HTTP to `10.0.2.2` is allowed in the debug manifest only |
| `flutter create` names the application id `com.paisa.paisa_mobile` | Set both `namespace` and `applicationId` to `com.paisa.mobile` and move `MainActivity` into that package |
| `google-services.json` in `android/` instead of `android/app/` | The build succeeds and Firebase is just unconfigured. Check the log for `FirebaseApp initialization successful` |
| The `google-services` Gradle plugin fails the build if the JSON is missing | It is applied only when the file exists, so the app builds before Firebase is registered |
| `FlutterActivity` cannot show the biometric prompt | `local_auth` needs a `FragmentActivity`; `MainActivity` extends `FlutterFragmentActivity` |
| `local_auth` on a phone with no screen lock | `isDeviceSupported()` is false. The lock cannot be turned on, and says why |
| A debug build looks fine and a release build breaks | R8, the secure window and biometrics differ. Test a release build before every distribution |

### 3.4 The emulator and `adb`

| Trap | What happens |
|---|---|
| The system PIN / biometric prompt is invisible to `adb screencap` | It is a secure window and the capture is **black**. `dumpsys window | grep mCurrentFocus` shows `BiometricPrompt`; `adb shell input text 1234` then `keyevent 66` answers it. `adb shell locksettings set-pin 1234` sets a throwaway PIN and `locksettings clear --old 1234` removes it |
| `FLAG_SECURE` makes a release build's screenshots black too | That is the point. Use a debug build to screenshot |
| The first launch after install, or after a density change, takes ~20 s | The Flutter splash stays up. Wait before tapping or the tap lands on the splash |
| `adb shell wm density 480` makes the emulator 360dp wide | The narrowest common phone. `wm density reset` undoes it. `adb shell cmd uimode night yes` flips system dark mode, which the app follows; `night no` undoes it |
| zsh treats `?` in an unquoted URL as a glob | `curl .../summary?month=2026-08` fails with "no matches found". Quote the URL |
| `java` on this Mac is only the macOS stub | `keytool` needs Android Studio's JDK by full path |
| `sed -i` on macOS needs `-i ''` | Use a small Python script with asserted anchors instead |

### 3.5 The API and the data

| Trap | What happens |
|---|---|
| The web's `currentPeriod()` caps the pay-cycle start day at 28 | The API takes 1–31 and clamps. For start days 29–31 the web's month label is one period behind on 61 days a year. `findings.md` F14 and `apps/web/BUG-pay-cycle-month-label.md` |
| An outgoing transfer lands in "Other" until it is categorised | A `Saving` budget share stays at ₹0 however much is moved (`findings.md` F15) |
| Without `?month=` the summary has no `period` | Always send the month, or the pay-cycle window cannot be shown |
| `GET /memberships` returns each member's `firebaseUid` | The app parses only the fields it shows and never logs the rest (`findings.md` F10) |
| Choosing a category **confirms** a payment | `PATCH …/category` sets `state: 'confirmed'`, so a reviewer can confirm. A bare state change needs editor (`findings.md` F11) |
| `Idempotency-Key` **is** honoured for a manual transaction | `CLAUDE.md` says it is ignored in production; `createTransaction` replays by key for 24 h. One key per form submission is safe (`findings.md` F3) |
| Opening the dashboard on the current month of an old ledger | Every tile reads zero, which looks like a failed import. Use the arrows; the sample data is August 2026 and the emulator's clock is October |

---

## 4. Working Style

- **Look at it.** A screenshot found two layout bugs that tests and the analyzer
  missed. Run on the emulator, in light and dark, at 360dp.
- **Verify against the API, not against an assumption.** The dashboard was checked
  against the server's own numbers for two books and four periods, including a pay
  cycle boundary.
- **Record, don't invent.** Fixtures come from a running API; ported logic is checked
  against a recording of the real function.
- **Say what was skipped.** A half-fix reported as complete is worse than no fix.
- **Deployment ends with a command, never a `git push`** — for the web and API,
  `./deploy/deploy.sh`; for the phone, the `flutter` build command for the channel.

---

## 5. Open Questions

| Question | Blocked on |
|---|---|
| Does the production sign-in work end to end? | Arjun signing in once with his own account |
| Should the light chart swatches be darkened for the phone? | A design call: it changes the brand palette (`findings.md` F9) |
| Bundle Geist? | Downloading `.ttf` files, and whether the system face is good enough |
| Do the household's phones need a read-only offline cache? | Real use; it was not chosen for v1 and fights the "never show stale numbers" rule |
| When does accepting an invitation move to the phone? | A deep-link and verified-email path (`prd.md` A3) |
