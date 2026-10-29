# Reclaim — API Specification

Base path: `/api/v1`. All endpoints (except `/auth/register`, `/auth/login`,
`/auth/refresh`, `/blocklist`, `/support/resources`, `/health`) require a valid JWT bearer
access token. Responses use `application/json`; errors use RFC 7807 `ProblemDetails`.

Legend: **[P1]** implemented in this pass, **[P2]** specified here but deferred (see
`ROADMAP.md`).

## Auth **[P1]**

| Method | Route | Notes |
|---|---|---|
| POST | `/auth/register` | email + password → creates `AppUser`, returns access+refresh token |
| POST | `/auth/login` | email + password → access+refresh token |
| POST | `/auth/refresh` | refresh token → new access+refresh token pair (rotation) |
| POST | `/auth/logout` | revokes the presented refresh token |
| DELETE | `/auth/account` | starts the account-deletion grace period (see `SECURITY.md`) |

## Profile & onboarding **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/profile` | current user's profile |
| PUT | `/profile` | update display name, recovery goal type, start date |
| POST | `/onboarding-responses` | submit onboarding questionnaire answers |
| GET | `/onboarding-responses` | fetch the latest submitted answers |

## Self-assessment **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/assessment/questions` | the questionnaire (versioned) and answer scale; anonymous, so the app can show it before an account exists |
| POST | `/assessment/submit` | `{ answers: { questionId: 0-3 } }` → score + risk level + recommended actions + disclaimer. Every question must be answered; score and level are always computed server-side |
| GET | `/assessment/history` | past results, newest first |

## Dashboard **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/dashboard/summary` | streaks, estimated money kept, monthly deposit/withdrawal/net-loss, goal progress snapshot |

## Gambling entries (loss tracker) **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/gambling-entries` | query `from`, `to` (both inclusive, on `occurredAtUtc`), `entryType`, `gamblingType`, `platform` (name, case-insensitive), paginated, newest first |
| POST | `/gambling-entries` | create an entry |
| PUT | `/gambling-entries/{id}` | edit an entry |
| DELETE | `/gambling-entries/{id}` | remove an entry |
| GET | `/gambling-entries/stats` | `?timeZone=` (IANA, default `Africa/Johannesburg`) → today / this week (from Monday) / this month / lifetime: `deposited`, `withdrawn`, `won`, `lost`, `netLoss` |

Entries take a free-text `platformName`; the backend groups names case-insensitively per
profile. `netLoss = (deposited − withdrawn) + (lost − won)`: people usually log either money
moved or outcomes, and the app should explain that logging both for the same money counts it
twice. A negative `netLoss` means the user is ahead.

## Goals **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/goals` | list with progress |
| POST | `/goals` | create |
| PUT | `/goals/{id}` | edit |
| DELETE | `/goals/{id}` | remove |
| POST | `/goals/{id}/contributions` | add a manual contribution |

## Urges **[P1]**

| Method | Route | Notes |
|---|---|---|
| POST | `/urges` | start an urge session (trigger + cooling-off duration) |
| PUT | `/urges/{id}/resolve` | record outcome: passed / gambled / abandoned |
| GET | `/urges` | history, for future pattern insights |

## Support resources **[P1, read-only content]**

| Method | Route | Notes |
|---|---|---|
| GET | `/support/resources` | verified South African support/counselling/self-exclusion/financial/emergency resources |

## Blocklist **[P1 endpoint, P2 client enforcement richness]**

| Method | Route | Notes |
|---|---|---|
| GET | `/blocklist?since={timestamp}` | incremental list of active gambling domains, versioned by `UpdatedAtUtc` |

## Journal **[P2]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/PUT/DELETE | `/journal-entries` | urge/mood/trigger/intensity/outcome/what-helped |
| GET | `/journal-entries/insights` | descriptive pattern surfacing, explicitly non-diagnostic |

## Protection lock **[P2 backend; P1 ships a local-only version on-device]**

| Method | Route | Notes |
|---|---|---|
| GET | `/protection/status` | current lock state |
| POST | `/protection/lock` | start a lock for a fixed duration |
| POST | `/protection/removal-request` | starts a 24h cooling-off removal request |
| DELETE | `/protection/removal-request/{id}` | cancel a pending removal request |

## Custom blocked domains **[P2 backend sync; P1 local-only]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/DELETE | `/custom-domains` | user-added domains, subject to `Removable` while protection is locked |

## Trusted contacts (accountability partner) **[P2]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/DELETE | `/trusted-contacts` | invite/list/revoke |
| POST | `/trusted-contacts/{id}/check-in` | request/record a check-in |

## Notification preferences **[P2 backend; P1 local device settings]**

| Method | Route | Notes |
|---|---|---|
| GET/PUT | `/notifications/preferences` | toggle categories, discreet wording |

## Conventions

- All list endpoints support `page`/`pageSize` and return `{ items, page, pageSize,
  totalCount }`.
- All monetary values are `decimal` ZAR, serialised as JSON numbers with 2 decimal places.
- All timestamps are ISO-8601 UTC. A timestamp sent without an offset is read as UTC.
- Create endpoints for user records (onboarding responses, assessments, gambling entries)
  accept an optional client-generated `id`, so records created offline keep their identity
  when synced. Reusing an existing id returns `409`.
- Required enum fields that are missing fail validation rather than defaulting.
- Mutating endpoints validate via FluentValidation before reaching a handler; validation
  failures return `400` with a `ProblemDetails` body listing field errors.
- Rate limiting: `/auth/*` endpoints are limited per-IP (see `SECURITY.md`); all other
  authenticated endpoints are limited per-user.
