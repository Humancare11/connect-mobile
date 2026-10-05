# Backend spec: `POST /auth/apple` (Sign in with Apple)

Required by App Store Guideline 4.8 because the iOS app offers Google login.
The Flutter app already calls this endpoint (`AuthService.appleLogin` /
`completeAppleRegistration` in `lib/services/auth_service.dart`). It mirrors the
existing `POST /auth/google` two-step flow. No backend code exists yet.

## Request

JSON body, no auth header. One endpoint, two phases chosen by whether `mobile`
is present.

| Field | Type | Phase | Notes |
|---|---|---|---|
| `identityToken` | string | both | Apple-signed JWT. **Required.** |
| `authorizationCode` | string | both | Single-use, ~5 min. See "Revocation". |
| `nonce` | string | both | The **raw** nonce. The app sent `SHA-256(nonce)` (hex) to Apple. |
| `firstName`, `lastName` | string | login | Only present on the user's first-ever Apple authorization for the app. |
| `email` | string | both | Only present on first authorization (login) / echoed back from the app (complete). May be a relay address. |
| `name` | string | complete | Full name collected/echoed by the app. |
| `mobile` | string | complete | E.164-style, same validation as `/auth/google`. |
| `privacyConsent`, `hipaaConsent` | bool | complete | Must both be `true`. |

## Verifying the identity token (always, both phases)

1. Fetch Apple's public keys from `https://appleid.apple.com/auth/keys` (cache;
   refresh on unknown `kid`). Verify the JWT signature (RS256).
2. Check claims:
   - `iss` == `https://appleid.apple.com`
   - `aud` == the iOS **bundle ID** `com.humancareconnect.app`
     (this is the audience for native iOS sign-in; a Services ID is only for web)
   - `exp` is in the future
   - `nonce` == `SHA-256(request.nonce)` as a lowercase hex string
3. Take `sub` as the stable Apple user ID. **Never trust `firstName`/`lastName`/
   `email` from the request body for identity**; identity is `sub` only.
   Use the token's own `email` / `email_verified` / `is_private_email` claims
   as the authoritative email.

The same token is sent in both phases (the app re-sends it from the profile
completion screen), so do **not** make the token or nonce one-time-use across
phases. Rejecting on `exp` (Apple tokens last ~10 minutes) is enough.

## Phase 1 — login probe (no `mobile` in the body)

Look up a user by `appleSub` (new column, unique, indexed).

- **Found** → respond exactly like a successful `/auth/google` login:
  the usual auth payload (`token`, `refreshToken`, `user`, ...).
- **Not found** → do **not** create anything. Respond `200`:
  ```json
  { "success": true, "isNewUser": true, "appleName": "<name or ''>", "appleEmail": "<email or ''>" }
  ```
  Prefill `appleName` from `firstName`+`lastName` in the body when present,
  `appleEmail` from the token's `email` claim.
- **Email already belongs to an existing password/Google account** (and the
  email claim is `email_verified` and *not* a private relay): link by setting
  `appleSub` on that account and log in, same policy as `/auth/google`. If your
  policy for Google is "never auto-link", apply the same here.

## Phase 2 — complete registration (`mobile` present)

Same verification, then create the user:

- Require `privacyConsent === true && hipaaConsent === true`, a valid `mobile`,
  and a non-empty `name`; otherwise `400` with a message the app can show.
- Create the patient with `appleSub`, `name`, `email` (token's claim, falling
  back to the body's `email`), `mobile`, consents, `emailVerified = true` when
  Apple says `email_verified`, and **no password**.
- If `appleSub` already exists (double-submit), just log in — be idempotent.
- Respond with the usual auth payload, as `/auth/google` does after
  completion.

## Name and email quirks (handle all of these)

- **Name is sent only once.** Apple returns the name solely the first time the
  user authorizes the app. If that attempt is abandoned (user quits before
  completing registration), a later attempt arrives with no name. The app then
  asks the user for their name and sends it as `name` in Phase 2 — require it.
  Never overwrite a stored name with an empty value.
- **Hidden / relay email.** When the user picks "Hide My Email", `email` is
  `<random>@privaterelay.appleid.com` and `is_private_email` is `true`.
  - Store it as the account email; do not reject it as "invalid".
  - Don't use it for duplicate-account detection against other accounts.
  - Mail only reaches the user if you register your sending domain/address in
    the Apple Developer portal (Certificates, Identifiers & Profiles → More →
    *Configure Sign in with Apple for Email Communication*) with SPF/DKIM set up.
    Appointment/receipt emails will otherwise silently bounce.
  - Users can disable forwarding at any time; treat email as best-effort and
    keep in-app / push notifications working.
- The token's `email` claim is present on every sign-in; the *body* fields
  (`firstName`, `lastName`, first-time `email`) are not.

## Errors

Use the same envelope as `/auth/google` (`{ "success": false, "message": "..." }`).
Suggested statuses: `400` bad/missing fields or consent not given, `401`
invalid/expired token or nonce mismatch, `409` conflicting account if you
choose not to auto-link, `5xx` Apple key fetch failed.

## Account deletion and revocation (App Review requires this)

Apple Guideline 5.1.1(v) expects the Apple grant to be revoked when an account
is deleted. In Phase 2, exchange `authorizationCode` at
`https://appleid.apple.com/auth/token` (using a client secret JWT signed with
your Sign in with Apple private key, `client_id` = bundle ID) and store the
returned `refresh_token` (encrypted) on the user. When the account-deletion
request (`/auth/account-delete-request`) is approved, call
`https://appleid.apple.com/auth/revoke` with that token. Do **not** exchange the
code in Phase 1 for an unknown user — the code is single-use and Phase 2 needs it.

## Prerequisites (Apple Developer portal, not code)

- Enable **Sign in with Apple** on the App ID `com.humancareconnect.app`.
- Create a Sign in with Apple **key** (.p8) → store Key ID, Team ID, key securely
  as backend secrets (needed for the code exchange / revocation above).
- Add the **Sign in with Apple** capability to the Runner target in Xcode.

## Also adjust

- Users table: `appleSub` (unique, nullable), `appleRefreshToken` (nullable,
  encrypted).
- Password-reset / "login with password" for Apple-only accounts: they have no
  password — return a clear message pointing to Sign in with Apple.
- Any `/auth/google`-style audit logging, rate limiting and session creation
  should apply equally here.

## Test checklist

- Valid token, new Apple user → `isNewUser: true`, no row created.
- Phase 2 with consents → account created, auth payload returned.
- Replaying Phase 2 → idempotent login, no duplicate.
- Token with wrong `aud` / bad signature / expired / wrong nonce → `401`.
- Relay-email user and returning user with no name in the body.
