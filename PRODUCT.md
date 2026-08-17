# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

StarForge education-center employees use this app on iOS and Android while teaching, moving between rooms, serving families, handling admissions, operating finance and print queues, or completing assigned work. Supported staff identities include teachers, teaching assistants, media staff, reception, admissions/sales, print operators, cashiers, and other non-management staff memberships returned by the StarForge Edu service. This is confirmed by the repository and the user's request to align mobile with the staff web product.

## Product Purpose

Give each signed-in staff member one permission-aware mobile workspace for the work their role can actually perform. Success means that the important staff-web workflows are available on mobile, real backend state is clear, and routine work can be completed without falling back to a desktop browser.

## Positioning

The workspace is derived from the authenticated person's role-native principal, branch and department scopes, and effective permissions. It does not ask users to choose a role and does not invent operational records when a service is unavailable.

## Operating Context

The product is used one-handed on phones and two-handed on tablets, in classrooms and operational areas with intermittent connectivity. Common work includes attendance, group and student follow-up, tasks, messages, forms, notifications, approvals, content, printing, meetings, admissions, finance, compliance, reporting, and personal employment records.

## Capabilities and Constraints

- Flutter is the established client stack and the app ships to Android and iOS.
- The production API is the StarForge Edu `/api/v1/` service; authorization and scope remain backend-authoritative.
- Management-only identities use the separate leadership product and remain rejected here.
- Existing secure session storage, protected-content controls, multilingual support, dark mode, and role-scoped behavior must be preserved.
- Feature parity means parity with staff-web workflows that the authenticated mobile user is permitted to use, not exposing every administrative operation to every role.
- Release signing credentials, store accounts, approved legal copy, and production QA identities remain organization-owned inputs.

## Brand Commitments

The product is StarForge EDU. The CEO web and staff web applications are the binding visual reference: warm editorial modern, Central Asian geometric undertone, restrained terracotta/saffron default palette, shared StarForge mark, clear operational hierarchy, and consistent light/dark variants. Native navigation, controls, safe areas, text scaling, and platform back behavior remain authoritative where web patterns do not translate directly.

## Evidence on Hand

- The adjacent `starforge_ceo_web` and `starforge_staff_web` repositories contain the incumbent design tokens, shell, components, and UX copy.
- `README.md` and `docs/backend_integration.md` document the implemented mobile contracts and release constraints.
- `lib/` contains the current production-connected feature implementation; `test/` contains contract, accessibility, responsive, privacy, and widget coverage.
- No approved marketing claims, universal credentials, production staff data, or store-signing assets are present and none may be fabricated.

## Product Principles

1. Backend truth over decorative completeness.
2. The right work for the signed-in role, with unavailable actions removed early.
3. Fast, legible, touch-first operation under real classroom and front-desk conditions.
4. One StarForge family across web and mobile, translated through native platform conventions.
5. Loading, empty, stale, offline, validation, and permission states are part of the product—not afterthoughts.

## Accessibility & Inclusion

Preserve full Uzbek, Russian, and English support; system text scaling through at least 200%; screen-reader semantics; 48 dp Android and 44 pt iOS touch targets; light/dark and increased-contrast legibility; reduced-motion behavior; safe-area handling; and usable phone, landscape, tablet, and split-window layouts.
