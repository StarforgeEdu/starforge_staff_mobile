# Starforge Staff

Starforge Staff is the Flutter mobile workspace for education-center employees. It ships one permission-aware Android/iOS client for teachers, teaching assistants, media staff, reception, admissions/sales, print operators, cashiers, and other staff memberships exposed by Starforge Edu.

The app is connected to the production Starforge Edu API at `https://starforge.78.111.91.113.nip.io`. A user signs in with a username and password; the authenticated account, branch memberships, role, language, and capabilities determine the workspace automatically. There is no role chooser. Management-only accounts such as CEO, owner, director, manager, and administrator are rejected because they use a separate product.

## Implemented product areas

- Uzbek-default UI with complete English and Russian switching and account-language synchronization
- Secure role login, saved-session restoration, required password change, name editing, privacy summary, and administration-led password reset guidance
- Real role workspaces backed by scoped API data; the app does not invent operational people, amounts, queues, salary records, or attendance values
- Teacher/assistant dashboard with assigned groups, lessons, rooms, student totals, meetings, notifications, announcements, and an honest unavailable state when recommendations cannot be supplied
- Assigned groups, student profiles, direct calling/messaging, approval-backed move/help/removal requests, monthly lesson history, explicit attendance marking, and published exam results
- Permission-aware task board with supported workflow states, assignment identity, creation, transitions, cached-state warnings, and responsive list/board layouts
- Participant-safe messaging with exact one-to-one thread matching, archive state, incremental updates, optimistic text/media/voice/file sending, and protected attachment access
- Searchable library with content folders/materials, teacher upload and approval flow, signed access URLs, view tracking, embedded PDF/image/video/audio/text viewers, and identity watermarking for view-only content
- Printer discovery, production print-job history, and scheduled print submission from approved content or a device file
- API-backed notifications, meetings, role operations, teacher payslips, and role-specific rulebook acknowledgements
- Persisted system/light/dark theme, accent, language, accessibility-aware motion, notification preferences, and local workspace preferences
- Native Android protected-window handling and iOS captured/app-switcher overlays for view-only learning content

## Run and verify

Prerequisites are Flutter 3.44 or newer plus the Android or iOS toolchain for the target platform.

```sh
flutter pub get
flutter run
```

Use an account provisioned by the education-center administration. The client contains no universal or sample password.

Before packaging a build:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

For an installable QA build:

```sh
flutter build apk --profile
```

For an organization release, provide `android/key.properties` or all four `STARFORGE_UPLOAD_*` signing variables, then run:

```sh
flutter build apk --release
flutter build appbundle --release
```

Release builds are never silently signed with Android's shared debug certificate. iOS archive/signing requires the organization's Apple team, provisioning profile, and an Xcode/macOS build host.

## Project map

```text
lib/
  core/             Session state, authorization, localization, theme, shared UI
  data/             Typed application and API response models
  features/         Auth, dashboard, groups, tasks, chat, library, print, profile
  services/         HTTPS API gateway and native content-protection bridge
android/             Android host, permissions, secure-window support, branding
ios/                 iOS host, localized permissions, capture privacy, branding
docs/                Verified API integration and release handoff
test/                Contract, privacy, accessibility, responsive, and widget tests
```

See [docs/backend_integration.md](docs/backend_integration.md) for the implemented API contract and operational release inputs.
