# O-AGENT Mobile — Flutter (Android + iOS)

**A real, cross-platform control surface for the existing O-AGENT development backend.**

This application is a runnable Flutter client, not a simulated agent dashboard. Its data comes from the Node control plane and outbound laptop gateway already maintained in this repository. It does **not** implement every future feature in `docs/PRODUCT_REQUIREMENTS.md`.

## What you can test

- Connect to your own backend using a **development operator token**.
- Monitor genuine online/offline workers from backend heartbeats.
- Choose an online machine and submit a **system information** task.
- Request a top-level **workspace inventory**; approve or reject it in the app.
- Read the actual result, task state, machine status, and persisted event history.
- Cancel pending/queued tasks when the backend permits.
- Refresh on demand, automatically every five seconds, and when the app resumes.
- Disconnect and remove the token from application memory.

Unsupported features are not hidden behind fake UI: AI chat, remote shell commands, live screen sharing, OAuth user login, cloud worker deployment, and push notifications are still future work.

## Quick start (Android / iOS)

Prerequisites:

1. Flutter stable SDK (3.50 or compatible) and a suitable Dart SDK.
2. Android Studio + Android SDK for Android, or **macOS + Xcode** for iOS.
3. The O-AGENT backend and gateway running; follow [MVP runbook](../../docs/MVP_RUNBOOK.md).

From this directory:

```bash
flutter create --platforms=android,ios --org com.omiiii --project-name o_agent_mobile .
dart run tool/prepare_platforms.dart
flutter pub get
flutter test
flutter run
```

The bootstrap uses Flutter's official platform templates, then adjusts local development networking. Platform scaffolding is generated rather than maintaining duplicate unverified generated code in Git.

### Android emulator

Start the Node backend on your computer and start the gateway in another terminal. The Android emulator maps host loopback to **`http://10.0.2.2:8787`**, the default shown by the app. Debug builds permit this local HTTP connection. Set the actual `OAGENT_API_TOKEN` in the app and connect.

For an installable debug APK:

```bash
flutter build apk --debug
```

Install `build/app/outputs/flutter-apk/app-debug.apk` on an Android device. For a real physical phone, use a reachable **HTTPS** backend address, not the emulator-only `10.0.2.2`. Configure TLS on a reverse proxy or secure tunnel, and do not publicly expose the dev control plane without additional security controls.

### iOS Simulator

Use a Mac with Xcode installed:

```bash
flutter devices
flutter run -d ios
```

The iOS Simulator normally reaches the development backend using **`http://127.0.0.1:8787`**. The platform setup script permits local networking. For a real iPhone, use a proper HTTPS backend and Apple development signing.

### Ready-to-download build artifacts

Open the [Flutter Mobile GitHub Actions workflow](https://github.com/omghotekar01-dotcom/O-AGENT-/actions/workflows/flutter-mobile.yml). Select a **successful** run and download:

- `o-agent-flutter-android-debug-apk`: Android debug APK, installable after accepting sideloading prompts.
- `o-agent-flutter-ios-simulator`: an unsigned **simulator-only** `Runner.app` ZIP for macOS. It is **not** an IPA for physical iPhones.

A physical iOS app requires Apple code signing, a team, and device or TestFlight provisioning; this repository intentionally does not include private signing certificates.

## API compatibility

Requires the existing Node API:

| Operation | HTTP endpoint |
|---|---|
| State | `GET /api/state` |
| Events | `GET /api/events?after=N` |
| Submit | `POST /api/tasks` with `Idempotency-Key` |
| Approve/reject | `POST /api/tasks/:id/decision` |
| Cancel | `POST /api/tasks/:id/cancel` |

The app sends `Authorization: Bearer <OAGENT_API_TOKEN>`. It does **not** embed a token, API key, or provider secret in source code.

For the server and gateway commands and known backend limitations, read [MVP_RUNBOOK.md](../../docs/MVP_RUNBOOK.md).

## Testing and reliability

```bash
flutter analyze
flutter test
```

The GitHub workflow runs Flutter analysis and unit/widget tests, then builds an Android APK and unsigned iOS Simulator app. A failed job means the corresponding artifact is **not** verified.

The backend remains development-grade: static shared tokens, single-process JSON persistence, 5-second polling, and no durable/cloud execution engine. **Do not deploy this token-based MVP as a public production service.** Move to per-user login, per-device scopes, TLS, audited approvals, and Postgres persistence before exposing sensitive machine controls.

## Project status

This Flutter client is the preferred cross-platform mobile client moving forward. The earlier native Kotlin prototype under `apps/android` is retained for historical continuity; it is not required to run this Flutter app.
