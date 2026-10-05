# 📐 Coding Rules

**Paisa Mobile — Android app**

The conventions the phone app holds to. Every rule exists because breaking it cost
something specific, and each one names that cost. The platform's rules in the repo's
[`docs/rules.md`](../../docs/rules.md) all apply (money is integer paise, history is not
optional, verify before you claim done); these are the phone's additions.

> **Last reviewed** 2026-10-05 · Operational rules live in the repo's `/CLAUDE.md`

---

## 1. The Short Version

| # | Rule | Cost of breaking it |
|---|---|---|
| 1 | Money is `BigInt` paise; there is no `double` on an amount | Rounding errors in a ledger; a wrong figure on a phone |
| 2 | A port of server logic is checked against a recording of the server | The phone and the web disagree about what month it is |
| 3 | The phone adds no rules; the server decides | Two answers to "what counts as spending" |
| 4 | Never show stale numbers as live; an error replaces the figures | Zeros beside an error read as "nothing happened" |
| 5 | Branch on a status or code, never on a message | A reworded server message breaks the app |
| 6 | Screens switch on one state; they never read a value that can vanish | A null-check crash during sign-out |
| 7 | Fixtures are recorded from the real API, never hand-written | Tests pass against a shape the server does not send |
| 8 | Look at it on a 360dp screen, light and dark, before it is done | A layout that overflows on the commonest phone |
| 9 | Verify before you claim done | Saying "fixed" about something that is not |
| 10 | Do the task asked; say what was left out | A half-fix reported as complete |

---

## 2. Money

```dart
// ✅  paise as a string over the wire, BigInt in Dart
formatMinorString('-6914200')   // −₹69,142

// ⛔  never
final rupees = amount / 100;
```

| Rule | Why |
|---|---|
| Parse with `parseMinor`, format with `formatMoney` | One place knows Indian grouping, the real minus sign and "paise only when non-zero" |
| Expenses negative, income and refunds positive | The sign carries direction |
| `kind` and `amountMinor` change **together** | `signedMinor(kind, amount)` takes the sign from the kind, so income cannot keep an expense's sign |
| Typed rupees go through `minorFromRupees` | It refuses a third decimal rather than rounding it away silently |
| A negative is never rendered as positive | `money()` once dropped the sign on the web and a deficit looked healthy |
| A percentage is a display figure, never an amount | `percentOf` truncates to one decimal exactly as the web does; use it for words, not sums |

---

## 3. Time, and Anything Ported From the Server

| Rule | Why |
|---|---|
| A date a person picks is midnight **in the book's timezone** (`BookClock.dateAt`) | A month-end salary otherwise slips into the next period |
| Timestamps are sent with `Z` or an offset, never a naked local time | The API rejects it as a 400 |
| **A port of server logic is checked against a recording of the server** | `currentPeriodLabel` is verified against 1,276 cases recorded from the real `period.js`. The web's hand-copied mirror was wrong for start days 29–31 for want of exactly this |
| Port the **API's** function, not the web's | The API is the source of truth; the web's mirror is a second copy that can drift |
| A shortcut with a known ceiling is marked `ponytail:` and names the ceiling | `BookClock` knows only fixed-offset zones; the comment says when to add the `timezone` package |

---

## 4. State

| Rule | Why |
|---|---|
| One `SessionState`; screens switch on it and nothing else | Five ways to be "not ready" collapse into five screens, not a tangle of flags |
| **A provider's inputs arrive as its argument, not from the session with `!`** | During sign-out the session has no book for a moment while the dashboard is still on screen. A `!` threw inside Riverpod |
| Read a provider's dependencies **before** the first `await` | After an await they may not be tracked |
| `retry: (count, error) => null` on the `ProviderScope` | Riverpod 3 retries a failed provider by itself and would hit the API repeatedly before showing the error |
| In a test, `container.listen(provider, ...)` before reading it | Riverpod 3 **pauses** a provider nothing is listening to; a bare `read` never completes. Ten tests timed out at 30 s on it |
| Nothing sensitive in preferences | Theme, last book and lock settings only. Firebase holds the session; the app never stores a token |
| Sign-out forgets the chosen book | The next person on the phone inherits nothing |
| **A write's answer is merged over what the screen holds** (`Transaction.fromJson(json, previous:)`) | The server's write routes answer with different parts of a payment, and there is no route to fetch one. Taking the answer whole dropped a payment's comments |
| A failed write changes nothing on screen, and says so in a sentence | Showing the attempted value as saved would be a lie about the ledger |

---

## 5. Screens and UI

| Rule | Detail |
|---|---|
| An error **replaces** the figures | `ErrorPanel`. A zeroed screen beside an error banner reads as "nothing happened"; old numbers read as live ones |
| Hide what the role cannot do; do not let it 403 | `Book.can(Capability.x)`. The server still checks every request |
| Status is a word, never colour alone | A pill, "Over the plan", "Yes" / "No" |
| Long money pairs go **under** the bar | `₹37,340 of ₹2,93,933.50` does not fit beside a label on 360dp. Use `Flexible`/`Wrap` wherever two pieces of text share a row |
| **One idempotency key per form**, kept across a lost connection, replaced after any answer the server gave | A retry after a dropped connection must add one payment, not two; a key reused with a changed body is a `409` |
| Guard on the phone what the server does not | The server lets a split payment's amount change, so the parts stop adding up. The phone locks it (`findings.md` F17) |
| Two buttons in one `Row` become a `Wrap` | "Forgot your password?" and "Request access" overflowed a 360dp phone by 226px |
| A `ColoredBox` inside a fixed-height `Row` needs `crossAxisAlignment.stretch` | Otherwise it sizes to nothing and the chart bar is invisible. Only a screenshot showed it |
| Cards in a row get `IntrinsicHeight` + `stretch` | Different content, different heights |
| Icon-only controls carry a tooltip | It is their accessible label |
| Dark mode is not an afterthought | Every screen is looked at in both; colours come from `context.paisa`, never a literal |
| Pure logic goes in a file with no widgets | `dashboard_logic.dart` is tested directly; the screen only draws it |

---

## 6. Tests

- Tests live in `app/test/`. **205 passing.** Run `flutter analyze` and
  `flutter test` before saying anything is done.
- **Fixtures are recorded from a running API** (`apps/api` in dev auth, memory store,
  sample data) into `test/fixtures/`. Never hand-write one, and never commit real
  financial data: record from the sample data or build the case in the test.
- A fixture changing is the signal the API moved. Update the model on purpose.
- Prefer an invariant to an example: `sum(byCategory) == spent + moved` catches more
  than any single expected figure.
- **Assert the setup succeeded.** A test that blames the code for a bad setup wastes
  an afternoon.
- Widget tests run at **360dp** (`physicalSize 1080x2400`, ratio 3). Flutter fails a
  test on any overflow, which is how the 226px one was found. The test font is wider
  than a real one, so treat an overflow there as real for long amounts.
- To reach something below the fold use `ensureVisible` then `pumpAndSettle`.
  `scrollUntilVisible` stops as soon as the widget is *built*, which a list does well
  beyond the viewport, so it can return without scrolling.
- Scope a finder when a sheet is over a screen: both have an `Email` field, and the split rows behind the category sheet repeat its names. Use `find.descendant(of: find.byType(BottomSheet), …)`.
- To test "a retry creates one row", make the fake server save the payment and then drop the reply (`FakeServer.dropNextCreateReply`), and assert both requests carried the same key.
- The system PIN / biometric prompt cannot be screenshotted (it is a secure window).
  Check focus with `dumpsys window | grep mCurrentFocus` and answer it with
  `adb shell input text`.

---

## 7. Security

| Rule | Why |
|---|---|
| Never log a token, an amount, a merchant or a response body | A finance app's logs are as sensitive as its screens |
| `AppConfig.devAuth` is `kDebugMode && DEV_AUTH` | A compile-time constant: a release build cannot turn it on whatever is passed. Checked by searching the release binary |
| The lock is a UI gate over the session, never a replacement | A forgotten PIN must never mean a locked-out account; "Sign out instead" is always there |
| Turning the lock on proves it works first | Nobody locks themselves out of a phone with no screen lock |
| Never type a real password into a test | The production sign-in is Arjun's step; tests use fakes and the local API's dev users |
| `APP_CHECK_MODE` stays `off` for the mobile launch | Play Integrity does not attest a sideloaded APK |
| Release builds are marked secure | Balances stay out of the recents thumbnail and recordings |

---

## 8. Android

| Rule | Why |
|---|---|
| `namespace` and `applicationId` are both `com.paisa.mobile` | The old app mixed two and `flutter create` defaults to a third |
| `INTERNET` in the main manifest; cleartext HTTP in the debug manifest only | `flutter create` grants `INTERNET` to debug alone, so a release build would have no network |
| `MainActivity` extends `FlutterFragmentActivity` | The biometric prompt needs a `FragmentActivity` |
| `google-services.json` lives in `android/app/` | In `android/` the build succeeds and Firebase is silently unconfigured |
| Test a **release** build before every distribution | R8, the secure window and biometrics differ from debug |
| One install channel per phone | The sideloaded APK and a Play build are signed with different keys and cannot update each other |

---

## 9. Before You Say It Is Done

```bash
cd "Mobile App/app"
flutter analyze                 # clean
flutter test                    # all green
# then run it on the emulator, in light and dark, at 360dp:
#   adb shell wm density 480    (and wm density reset afterwards)
#   adb shell cmd uimode night yes   (and night no afterwards)
flutter build apk --release --dart-define=API_URL=https://paisa.easylancefreelance.com
```

And update the docs the change touches (below). A stale `build/` can hide a mistake;
`flutter clean` if a build behaves oddly.

| If you changed… | Update |
|---|---|
| A requirement's state, or added/dropped a feature | `docs/prd.md` |
| Packages, folder layout, a route the app calls, auth, security | `docs/architecture.md` |
| A convention, or hit a bug a rule would have prevented | `docs/rules.md` |
| Tokens, a component, layout, or user-facing copy | `docs/design.md` |
| Finished, started or reprioritised work | `docs/tasks.md` **and** the repo's `TODO.md` |
| Made a decision, or paid for a new trap | `docs/memory.md` |
| Found something that changes the plan | `docs/findings.md` |

Bump **Last reviewed** on any doc you touch, and the status line in `README.md`.

---

## 10. Comments

Comment the **why**, never the what, and one short line. A comment explaining a line
you can read is noise; one explaining a decision you would otherwise undo is the
point. Mark a deliberate shortcut with `ponytail:` and name its ceiling.

```dart
// ✅
// Riverpod 3 pauses a provider nothing is listening to, so a bare read would
// never complete. In the app a screen is always listening.

// ⛔
// Get the summary
```

---

## 11. Scope

Do the task asked. If you find a real problem with it, say so in a sentence and keep
building; if it belongs to another part of the repo, write it up where it lives and
do not fix it in passing (the web's month-label bug is in `apps/web/`, written up in
its own file). Deliver the whole thing or say plainly what you left out: **a half-fix
reported as complete is worse than no fix.**
