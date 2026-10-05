# 🔥 Registering the Android app in Firebase

**Paisa Mobile — Android app**

> **Status** Done 2026-10-05. Kept for the release and Play SHA-1s (Phase 8), the
> iOS app (Phase 10), and anyone setting up another environment.

Phase 0 task 0.3 — **Arjun's step**. About ten minutes. Nothing here changes the
server: the API already verifies any token issued by the `paisa-easylance`
project, whichever app (web or Android) it came from.

> **Last reviewed** 2026-10-05

## What you need

- Access to the Firebase console as an owner of `paisa-easylance`.
- Nothing from the repo. The project is created in Phase 0; the file you download
  is dropped into it afterwards.

## Steps

1. Open <https://console.firebase.google.com> and choose the **`paisa-easylance`**
   project.
2. Click the **gear icon → Project settings → General**.
3. Scroll to **Your apps**. You will see the web app. Click **Add app → Android**
   (the robot icon).
4. Fill the form:

   | Field | Value |
   |---|---|
   | Android package name | `com.paisa.mobile` — exactly, it can never change |
   | App nickname | `Paisa Android` |
   | Debug signing certificate SHA-1 | `5E:4D:10:4B:D1:C8:CE:A9:D7:52:A6:3F:BB:37:99:AC:68:AE:F4:AA` |

   That SHA-1 is the debug certificate on this Mac (`~/.android/debug.keystore`).
   It identifies a development key, not a secret. It is optional for email and
   password sign-in but costs nothing to add now.
5. Click **Register app**.
6. Click **Download google-services.json**. Save it somewhere you can find it.
7. **Skip the remaining console steps** ("Add Firebase SDK", "Next", etc.). The
   project is wired up in code. Click through to **Continue to console**.
8. Put the file here, with exactly this name:

   ```text
   Mobile App/app/android/app/google-services.json
   ```

   If `app/` does not exist yet, the Phase 0 scaffold below creates it. Tell me
   when the file is in place and I will wire it in.

## Check these while you are in the console

| Where | What to confirm |
|---|---|
| **Authentication → Sign-in method** | **Email/Password** is enabled (the web already relies on it) |
| **Authentication → Settings → User actions** | **Enable create (sign-up)** is **unchecked**. The app is invite-only; this is also a standing item in `TODO.md` |
| **App Check** | Leave it **unregistered** for Android. Enforcing it would lock out sideloaded builds (finding F1) |
| **Project settings → Cloud Messaging** | Firebase Cloud Messaging API (V1) shows as **Enabled**. Nothing to do for now; Phase 7 uses it |

## Later (not now)

| Phase | Add |
|---|---|
| 8 | The **release** signing certificate's SHA-1 (from the keystore you create) |
| 8 | The **Play app-signing** SHA-1, once the app exists in Play Console, because Play re-signs the app |
| 10 | An iOS app, plus an APNs key for push |

## Is `google-services.json` a secret?

No. It holds the project number, the app ID and a client API key that identifies
the project, not a credential. Google documents it as safe to commit. It is still
tied to this project, so keep it in the repo with the app and do not post it
publicly out of habit.

## If something goes wrong

| Symptom | Likely cause |
|---|---|
| Sign-in works on the web but the app says `invalid-api-key` or `app not authorized` | `google-services.json` from a different project, or the package name differs from `com.paisa.mobile` |
| Sign-in succeeds but every API call is `401 INVALID_TOKEN` | Server's `FIREBASE_PROJECT_ID` differs from the project the app registered in. It should match `paisa-easylance` |
| `403 INVITE_REQUIRED` after signing in | The account has no household. It needs an invitation or master-admin approval, not a Firebase change |
