# Yardline App

The standalone Flutter worker application for Yardline. This repository contains only the mobile client; it uses the existing Yardline backend and shared yard data.

## Download and install on Android

**[Download Yardline.apk](https://github.com/bhavya03-03/Yardline-App/releases/download/mobile-debug-v1.0.0/Yardline.apk)**

[Release page](https://github.com/bhavya03-03/Yardline-App/releases/tag/mobile-debug-v1.0.0)

Open the download link on your Android phone, download the file, and tap it to install. Allow installation from your browser or file manager if Android asks. Android 7.0 or newer is required. This is a debug APK, approximately 200 MB.

The APK is distributed as a release asset because it exceeds GitHub's 100 MB regular repository-file limit.

SHA-256: `87f2e8eb8fb8bee1e1f100a7082a3d83e35519406773b11a7834e41231614c8c`

## Features

- Native camera/photo capture and on-device ML Kit OCR.
- Editable recognized container numbers with ISO 6346 format and check-digit validation.
- Shared container lookup and recorded location details.
- Registration, available-position selection, relocation, verification, and gate-out.
- Movement history and foreground synchronization with the web dashboard.
- Encrypted local drafts/cache and review of interrupted operations; no automatic POST replay.

## Mobile operations and the web dashboard

Use this app on the ground to photograph and register arrivals, confirm ISO 6346 container identities, assign actual yard positions, relocate containers, and record dispatches. The website is the desktop view for yard maps, occupancy, inventory, movement history, filtering, and exports. Its Register Container tab and registration shortcuts have been removed; mobile registration still uses the same existing API.

Both clients share one backend and database. Mobile writes become visible on the website through `/api/state` reads every 30 seconds while the dashboard is visible, or when the page regains focus, becomes visible, or reconnects. Existing web move, dispatch, verification, and administration controls are still available; the website is not fully read-only.

No app code change or new APK is needed for the website-tab removal. The APK linked above continues to use the existing deployed API. The [Yardline Project repository](https://github.com/bhavya03-03/Yardline-Project) contains both source projects and a shared overview.

Integration references: [API contract](MOBILE_API_CONTRACT.md), [backend integration audit](MOBILE_INTEGRATION.md), and [implementation guide](MOBILE_IMPLEMENTATION_GUIDE.md). These guides include historical findings and proposals; use this README for the current mobile project location and capabilities.

## Existing backend

The default API is `https://yardline-bhavya0303.netlify.app`. Tap **Enter demo yard** to select the existing operator persona. The current deployment reports demo authentication and PostgreSQL persistence. The web application remains in the separate [Yardline repository](https://github.com/bhavya03-03/Yardline).

No new backend or database is included here. The mobile client calls the existing Yardline HTTP API; it does not perform direct database table CRUD.

Existing Supabase worker authentication is supported separately through build configuration, but a project URL/public key and provisioned worker memberships are not configured or verified in the default demo APK. Do not create another Supabase project. Never place database credentials, service-role keys, or private API keys in this application.

## Run from source

Install Flutter 3.47.7 or a compatible SDK (Dart 3.13.5+) and the Android SDK. Open this repository as the Flutter project; `pubspec.yaml` is at its root.

```sh
flutter doctor -v
flutter pub get
flutter run -d <ANDROID_DEVICE_ID>
```

Optional existing Supabase worker-auth configuration:

```sh
flutter run --dart-define=YARDLINE_API_BASE_URL=https://<EXISTING_API_HOST> --dart-define=YARDLINE_AUTH_MODE=supabase --dart-define=SUPABASE_URL=https://<EXISTING_PROJECT>.supabase.co --dart-define=SUPABASE_ANON_KEY=<PUBLIC_PUBLISHABLE_OR_ANON_KEY>
```

Public URL/key configuration is compiled into the app. Supply worker passwords through the sign-in UI, never as Dart defines. The same existing backend must already use Supabase authentication and authorize the worker for the selected yard.

## Verify and build

```sh
flutter analyze
flutter test
flutter test integration_test/native_test.dart -d <ANDROID_DEVICE_ID>
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

Verified in the original development workspace: clean analysis, 23 unit/widget tests, 3 native emulator integration tests, successful Android debug build/installation, real raster-image OCR, Android photo-picker OCR, and live shared API reads. Operational writes were exercised with isolated fixtures. The release asset was copied from that verified build.

Physical-device camera quality/permissions in yard conditions, live operational acceptance testing, and Supabase worker-account authentication/memberships still require verification. iOS scaffolding is included (minimum iOS 15.5); iOS builds were not verified on the Windows development host.
