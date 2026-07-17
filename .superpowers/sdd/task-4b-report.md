# Task 4B Report: Observer Auth Contract Integration

Status: DONE_WITH_CONCERNS (review findings resolved)

Base: `84c9a9b`

## Implemented

- Reconciled Sign in with Apple with API commit `6cb1cae`:
  - strict camelCase `authorizationCode`, `identityToken`, `nonce`, and optional `fullName`
  - strict `{csrfToken,user}` decoding, nullable relay email, exact `OBSERVER` role
  - dedicated `/auth/me` observer DTO with matching `id` and `userId`
- Added exact protected-mutation semantics:
  - one secure, exact-name `fluke_csrf` cookie applicable to the HTTPS API origin
  - bounded base64url-safe value and rejection of missing, duplicate, lookalike, insecure, or domain-mismatched cookies
  - exact `200 {"ok":true}` handling for logout and account deletion without weakening existing 204 helpers
- Added stateful Apple authorization:
  - 32 bytes from `SecRandomCopyBytes`, unpadded base64url
  - separate one-use pending nonces for sign-in and deletion
  - `.fullName` and `.email` scopes
  - identity token and authorization code both required
  - cancellation, malformed results, and replay clear or reject pending state before HTTP
- Added fresh Apple reauthentication UI after destructive deletion confirmation.
- Preserved optional anonymous browsing, authenticated state/cookies after failed deletion, and server-success-before-local-cleanup ordering.
- Kept credentials and CSRF material out of Keychain and logging; the existing Keychain entry remains a non-secret Boolean reauthentication hint.

## Review Hardening

- Matched API commit `6cb1cae` exactly for CSRF: one secure, exact-host cookie at `/api/v1`, with an exact `43-base64url.43-base64url` token and response/cookie equality.
- Added a typed JSON retry policy and disabled retries only for the one-use Apple authorization-code exchange; existing JSON and multipart callers retain their prior transient retry default.
- Serialized sign-out and deletion with an observable account-mutation gate and generation checks so an older completion cannot restore authenticated state after a newer expiration.
- Made Apple authorization flow state observable, cancelled duplicate configuration without replacing its valid pending nonce, and disabled conflicting account controls while authorization or mutation work is pending.
- Enforced the API's exact 120-character observer display-name maximum on decoded current-user and sign-in responses.

## TDD / Security Evidence

- Initial contract tests failed to compile against the old two-field credential, bodyless deletion, 204 response, and API client without cookie-backed CSRF support.
- One-use nonce regression proof:
  - temporarily removed nonce consumption
  - `AppleAuthorizationFlowTests` failed with `xcodebuild` exit 65
  - restored consumption
  - the same focused test passed with exit 0
- Focused FlukeKit auth/mutation run: 20 tests across 3 suites passed, including 9 malformed credential cases, 4 malformed CSRF cases, strict response keys/role, exact status, and fresh deletion body.
- Focused app auth/nonce run: 12 tests passed before the final full app run; final full app run included all added tests.
- Review RED proof: focused package tests initially failed to compile because the typed no-retry JSON option and pending-control state did not exist; production code was added only after those tests.
- Review focused GREEN proof: 23 FlukeKit auth/mutation tests, 4 You interaction tests, and the focused app AuthSession/Apple authorization targets passed.
- Secret/log diff scan found no new `print`, logger, `os_log`, or credential-to-Keychain path.

## Fresh Verification

- Full `FlukeKit`: passed; source coverage 92.03% (1860/2021).
- Full `FlukeUI`: passed; source coverage 93.33% (532/570).
- Full `FlukeFeatures`: 65 Swift Testing cases plus legacy render tests passed; selected logic coverage 87.87% (840/956).
- Full app unit target on iPhone 17 / iOS 26.0.1: 31 tests plus parameterized cases, 0 failures; the public-browse UI boundary test also passed.
- App line coverage: 85.32% (901/1056), above the 80% gate.
- Generic iOS Simulator Release build: exit 0.
- `swift-format lint --strict` on every changed Swift file: exit 0.
- `git diff --check`: exit 0.

## Concerns / Remaining Launch Gates

- No live Apple authorization or production API endpoint was called, as required by this task.
- Account capability must remain false until the matching API routes are deployed and sign-in, restore, logout, failed deletion, and successful deletion are smoke-tested on a physical device.
- The API cookie store receives `Set-Cookie` through the configured `URLSession`; transport-only tests seed an isolated cookie store rather than simulating response cookie processing.
