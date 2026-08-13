# Starforge Edu integration

The mobile client uses the live HTTPS origin `https://starforge.78.111.91.113.nip.io` and the versioned `/api/v1/` API. The origin currently reports healthy responses from `/healthz/live` and `/healthz/ready`, and publishes its OpenAPI document at `/api/schema/`.

## Source and deployment state

The Flutter client and the adjacent Starforge Edu source implement the contracts in this document. They are not a substitute for an approved production deployment. On 2026-08-12, read-only probes confirmed that the live service was healthy and existing authenticated messaging-event and notification-preference routes rejected anonymous requests with `401`, as expected. The following newly completed source routes still returned `404` from the live host:

- `/api/v1/org/app-status/`
- `/api/v1/printing/upload-url/`
- `/api/v1/cohorts/{id}/cycle-progress/`
- `/api/v1/cohorts/{id}/teaching-progress/`

Until the reviewed backend revision and migrations are deployed, the installed QA app may truthfully show those dependent features as unavailable. Production rollout requires the backend release runbook, backups, migration gates, the updated OpenAPI contract, and post-deployment role-scoped smoke tests.

## Authentication and account routing

- `POST /api/v1/auth/role-login/` accepts the role-native username/password plus a stable, securely stored device identifier and platform.
- The returned bearer access value is stored with `flutter_secure_storage`; it is never stored in shared preferences or logs.
- `GET /api/v1/users/me/` restores identity, names, preferred language, memberships, scopes, and read-only state.
- A transient connectivity failure preserves the saved access value. A confirmed `401` clears it.
- `POST /api/v1/auth/password/change/` handles required and voluntary password changes; `POST /api/v1/auth/logout/` revokes the current session.
- Role and permissions come only from the authenticated response. The client does not ask the user to choose or claim a role.
- Exact management memberships are routed away from this staff product. Substrings such as “Admissions” are not accidentally rejected as “Admin.”

The API is the authorization source of truth. The client also removes unavailable actions early for clarity, but client-side checks never replace backend scoping.

## Connected domains

| Product area | API surface |
| --- | --- |
| Profile | `/users/me/`, `/auth/password/change/` |
| Groups and students | `/cohorts/`, `/cohorts/{id}/cycle-progress/`, primary-teacher `/cohorts/{id}/teaching-progress/`, `/students/` |
| Lessons and attendance | `/schedule/lessons/`, `/attendance/records/`, `/attendance/cohorts/{id}/dashboard/`, `/attendance/lessons/{id}/mark/` |
| Exams | `/academics/exams/`, `/academics/exams/{id}/results/` |
| Teacher dashboard | `/teachers/dashboard/`, `/meetings/upcoming/`, `/notifications/`, `/org/app-status/` |
| Tasks | `/tasks/`, `/tasks/mine/`, `/tasks/{id}/transition/` |
| Messaging | `/messaging/contacts/`, `/messaging/threads/`, thread messages/read state, durable `/events/` recovery, `/ws/messaging/threads/{id}/`, and attachment upload/access grants |
| Library | `/content/folders/`, `/content/files/`, `/content/materials/`, upload/confirm/access/view/approval actions |
| Printing | `/printing/printers/`, `/printing/jobs/`, `/printing/upload-url/`, and secure content/file submission |
| Staff requests | `/approvals/requests/` with the cohort branch and student identity in structured payload data |
| Rules and payroll | `/rulebook/rules/mine/`, acknowledgement actions, `/payroll/payslips/mine/` |
| Notifications | feed, unread count, read actions, and `/notifications/preferences/` |
| Role operations | scoped meetings, CRM leads, finance invoices, cashier shifts, content, and print queues as appropriate to the authenticated role |

Collection requests follow the Starforge envelope and pagination contract. The gateway walks bounded pages for workspace collections and fails rather than presenting silently truncated attendance history. Conversations use authenticated WebSockets for live hints and durable HTTP event cursors for ordered gap recovery, with REST snapshot recovery and bounded polling fallback. Dates are sent as ISO-8601 values and displayed with the active app locale.

## Files and protected content

Messaging attachments and content-library files use short-lived, owner-bound upload grants. The client uploads directly to the granted object-storage URL, validates the HTTP result, and then confirms library files before exposing them. Download/playback URLs are requested only when needed.

For resources marked view-only:

- the app renders supported PDF, image, video, audio, and text content internally;
- the external download action is absent;
- the content is visibly watermarked with the signed-in identity;
- Android enables `FLAG_SECURE` while viewing;
- iOS obscures captured and app-switcher content and displays a localized Dynamic Type overlay.

iOS cannot guarantee that the operating system will block every screenshot. Product copy therefore states the controls that are actually enforced rather than making an impossible guarantee.

## Data-integrity decisions

- Missing attendance is “unmarked,” never silently converted to present or 0%.
- A lesson is complete only when every roster student has a mark; partial registers remain visibly partial.
- Attendance save is disabled until the register is complete and leaving with changes requires confirmation.
- Direct-message reuse requires exactly the current user and selected contact; a group thread containing that contact is never reused.
- Missing phone, employment, exam, presence, contract, or AI data stays visibly unavailable. The client does not fabricate replacement values.
- Study month is an explicit bounded cohort value. Only the exact primary teacher may edit it, level text, or the 8/12 cadence from the staff app; assistants and co-teachers remain read-only.
- The current payroll engine produces immutable teacher payslips only. Non-teacher compensation remains hidden until the organization defines and implements a generic staff employment and payout-policy contract.
- Cached data remains visible after a refresh failure with an explicit stale-state warning.
- Read-only accounts cannot mutate profile, tasks, attendance, approvals, rules, content, or preferences.

## Release and operations

The following organization-owned inputs remain outside source control:

- Android upload keystore and passwords
- Apple distribution team, certificates, and provisioning profile
- approved, versioned legal/privacy policy text and public policy URL
- notification provider configuration if remote push delivery is enabled later
- production staff QA accounts for each supported membership and branch scope

Required pre-release verification:

1. Run Flutter format, analysis, and the full widget/contract test suite.
2. Verify live and ready health endpoints plus the published OpenAPI document.
3. Exercise authenticated role-by-role smoke tests with organization-provided QA accounts.
4. Check narrow phone, tablet, landscape, 200% text, dark mode, all three languages, reduced motion, low network, and stale-data states.
5. Build and verify Android signing/package metadata; archive and validate iOS on macOS/Xcode.
6. Review the final privacy policy, retention, payroll visibility, protected-content, and notification settings with the organization before store submission.

Android API 24 support also depends on serving a compatible RSA certificate chain. The app includes the official ISRG Root X1 trust anchor, while the backend Caddy source is configured for `rsa2048`; that server configuration must be deployed and verified on a real Android 7.0 device before API 24 support is claimed.
