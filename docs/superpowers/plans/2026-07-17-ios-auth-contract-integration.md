# iOS Observer Auth Contract Integration Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` and TDD. Do not enable production account capabilities until live E2E certification.

**Goal:** Make the optional Sign in with Apple, session restore/logout, Logbook, and account-deletion client exactly compatible with the approved standalone API contract without persisting credentials or CSRF secrets.

**Architecture:** A stateful `@MainActor` Apple authorization flow generates one cryptographically random base64url nonce per request, assigns it to `ASAuthorizationAppleIDRequest.nonce`, and consumes it exactly once with the returned identity token and authorization code. `AuthService` decodes `{csrfToken,user}`, accepts nullable Apple relay email, and sources the double-submit CSRF value from the non-HttpOnly `fluke_csrf` cookie for every protected mutation. Account deletion requires a new Apple authorization result and never sends a bodyless DELETE. Cookie storage remains the session source of truth; Keychain retains only the existing non-secret reauthentication hint.

## Task 4B: Reconcile iOS and API Observer Lifecycle Contracts

**Files:**
- Modify: `Packages/FlukeKit/Sources/FlukeKit/API/APIClient.swift`
- Modify: `Packages/FlukeKit/Tests/FlukeKitTests/MutationAPIClientTests.swift`
- Modify: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/AuthModels.swift`
- Modify: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/AuthService.swift`
- Modify: `Packages/FlukeKit/Tests/FlukeKitTests/AuthServiceTests.swift`
- Modify: `App/Fluke/Auth/AppleAuthorizationAdapter.swift`
- Create: `App/Fluke/Auth/AppleAuthorizationFlow.swift`
- Modify: `App/Fluke/Auth/AuthSession.swift`
- Modify: `App/FlukeTests/AuthSessionTests.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/YouView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/YouInteraction.swift`
- Modify: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/YouInteractionTests.swift`
- Modify: `App/Fluke/RootScene.swift`

**Exact contracts:**
- Sign-in request: strict camelCase `{authorizationCode, identityToken, nonce, fullName?}`.
- Sign-in response: strict `{csrfToken,user}`; user role must equal `OBSERVER`; `email` is nullable.
- Logout: `POST /api/v1/auth/logout`, header `x-fluke-csrf` from the validated `fluke_csrf` cookie, response `200 {ok:true}`.
- Delete: `DELETE /api/v1/auth/account` with the same CSRF header and a fresh strict `{authorizationCode, identityToken, nonce}` body, response `200 {ok:true}`.
- Restore: `GET /api/v1/auth/me` decodes a dedicated observer user DTO; 401 expires the local session.

- [ ] **Step 1: Write failing contract and nonce lifecycle tests**

Cover exact JSON keys, missing/blank token/code/nonce rejection, one-use pending nonce, cancellation clearing the nonce, malformed/oversized values, nullable email, wrong role, wrapper decoding, missing/malformed CSRF cookie, header attachment, 200 `{ok:true}`, and deletion requiring a fresh credential. Prove raw credential values never enter logs, Keychain, or errors.

- [ ] **Step 2: Implement bounded cookie-backed CSRF mutation APIs**

Expose a focused API client method that reads exactly one secure `fluke_csrf` cookie applicable to the API origin, validates 32...512 safe characters, rejects duplicate/lookalike/domain-mismatched cookies, and adds `x-fluke-csrf`. Add typed `postOK` and `deleteOK` response methods without weakening existing `204` helpers.

- [ ] **Step 3: Implement the stateful Apple authorization flow**

Generate at least 32 bytes with `SecRandomCopyBytes`, encode unpadded base64url, set the exact nonce on the Apple request, request `.fullName` and `.email`, require non-empty UTF-8 identity token and authorization code, and consume the pending nonce once. Cancellation and malformed results must clear pending state and perform no HTTP request.

- [ ] **Step 4: Update session and You deletion UX**

Store only the authenticated user in memory and the existing non-secret Keychain hint. Present a dedicated Sign in with Apple reauthentication action after destructive deletion confirmation; do not call deletion until that fresh authorization succeeds. On failed deletion preserve signed-in state and cookies with retryable copy. On success clear cookies, hint, and queued account association only after API success.

- [ ] **Step 5: Verify and independently review**

Run focused FlukeKit, FlukeFeatures, and app auth tests; all package suites with the exact coverage gates; generic iOS Simulator build; `swift-format lint --strict`; `git diff --check`. Commit as `fix: align observer account lifecycle contracts`. Do not call live Apple or production account endpoints in this task.

**Launch gate:** Account capability stays false until the matching API routes are deployed and a physical-device Apple sign-in/logout/deletion smoke test passes.
