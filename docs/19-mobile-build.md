# 19 - Mobile Build (Android / iOS)

Flutter is cross-platform; the same `app/` code builds for mobile. Mobile unlocks
field collection (camera for receipts, offline-first, biometric unlock).

## Prerequisites
- Flutter 3.47.7 (pinned) with Android/iOS toolchains.
- Android Studio / Xcode.
- A Supabase project URL + anon key (same as web).

## One-time setup
```powershell
cd app
flutter create --platforms android,ios .
```
This adds `android/` and `ios/` directories without overwriting `lib/`.

## Android
- Set `applicationId` in `android/app/build.gradle` (e.g. `com.namunaone.nhisab`).
- Add internet permission (already default).
- For release: create a keystore, configure `key.properties`, build:
  `flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- For Play Store: `flutter build appbundle --release ...`.

## iOS
- Set bundle identifier in Xcode (`com.namunaone.nhisab`).
- Configure signing team.
- `flutter build ipa --release --dart-define=...`.

## Offline / mobile specifics
- Hive cache + outbox already work offline; ensure `CacheService.init()` runs at startup (it does in `main.dart`).
- Add `local_auth` for biometric unlock (optional, future).
- Add `image_picker` for receipt capture (optional, future).

## CI
Add a `mobile.yml` workflow that runs `flutter build apk --debug` on PRs to catch
compile regressions. Store signing secrets in GitHub Secrets (never commit).

## Notes
- The web PWA remains the primary Tier A/B delivery; mobile is additive.
- Push notifications on mobile require FCM/APNs setup (not implemented).